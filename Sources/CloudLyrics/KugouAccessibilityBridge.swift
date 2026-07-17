import ApplicationServices
import Foundation

struct KugouAXTextEntry: Equatable {
    var value: String
    var position: CGPoint
}

struct KugouAXPlaybackState: Equatable {
    var title: String
    var artist: String
    var progress: TimeInterval
    var duration: TimeInterval
}

struct KugouProgressEstimator {
    private var trackKey: String?
    private var rawProgress: TimeInterval?
    private var rawBoundaryAt: Date?
    private var lastObservedAt: Date?
    private var lastMovementAt = Date.distantPast
    private var estimatedProgress: TimeInterval?

    mutating func update(trackKey: String, rawProgress: TimeInterval, now: Date) -> (progress: TimeInterval, isPlaying: Bool) {
        guard self.trackKey == trackKey else {
            self.trackKey = trackKey
            self.rawProgress = rawProgress
            rawBoundaryAt = nil
            lastObservedAt = now
            lastMovementAt = .distantPast
            estimatedProgress = rawProgress
            return (rawProgress, false)
        }

        if let previousRaw = self.rawProgress, abs(previousRaw - rawProgress) > 0.05 {
            let isNormalTick = rawProgress > previousRaw && rawProgress - previousRaw <= 1.5
            if isNormalTick, let lastObservedAt {
                // KuGou exposes only whole seconds. The actual boundary occurred
                // between the preceding observation and this one, so use their
                // midpoint as the sub-second anchor.
                rawBoundaryAt = lastObservedAt.addingTimeInterval(now.timeIntervalSince(lastObservedAt) / 2)
            } else {
                // A seek or track reset is not a clock tick and must not inherit
                // interpolation from the old position.
                rawBoundaryAt = now
                estimatedProgress = rawProgress
            }
            lastMovementAt = now
        }

        self.rawProgress = rawProgress
        lastObservedAt = now
        let isPlaying = now.timeIntervalSince(lastMovementAt) < 1.4
        if isPlaying, let rawBoundaryAt {
            // Never run into the next second without KuGou confirming it. This
            // keeps pause detection and delayed AX updates from drifting.
            let fraction = min(0.95, max(0, now.timeIntervalSince(rawBoundaryAt)))
            estimatedProgress = max(estimatedProgress ?? rawProgress, rawProgress + fraction)
        } else {
            estimatedProgress = min(max(rawProgress, estimatedProgress ?? rawProgress), rawProgress + 0.95)
        }
        return (estimatedProgress ?? rawProgress, isPlaying)
    }
}

enum KugouAXSnapshotParser {
    private static let elapsedRegex = try! NSRegularExpression(pattern: #"^\d{1,3}:\d{2}\s*$"#)
    private static let durationRegex = try! NSRegularExpression(pattern: #"^/\s*\d{1,3}:\d{2}\s*$"#)

    static func parse(_ entries: [KugouAXTextEntry]) -> KugouAXPlaybackState? {
        guard let durationEntry = entries.last(where: { matches(durationRegex, $0.value) }),
              let progressEntry = entries.filter({ matches(elapsedRegex, $0.value) })
                .min(by: { abs($0.position.y - durationEntry.position.y) < abs($1.position.y - durationEntry.position.y) }),
              let duration = parseClock(durationEntry.value.replacingOccurrences(of: "/", with: "")),
              let progress = parseClock(progressEntry.value) else { return nil }
        let titleEntry = entries.filter {
            $0.value.contains(" - ") && abs($0.position.y - progressEntry.position.y) < 20
        }.min(by: { abs($0.position.x - progressEntry.position.x) < abs($1.position.x - progressEntry.position.x) })
        guard let combined = titleEntry?.value.trimmingCharacters(in: .whitespacesAndNewlines),
              let separator = combined.range(of: " - ", options: .backwards) else { return nil }
        let title = combined[..<separator.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = combined[separator.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !artist.isEmpty else { return nil }
        return .init(title: title, artist: artist, progress: progress, duration: duration)
    }

    private static func matches(_ regex: NSRegularExpression, _ value: String) -> Bool {
        let range = NSRange(value.startIndex..., in: value)
        return regex.firstMatch(in: value, range: range)?.range == range
    }

    private static func parseClock(_ value: String) -> TimeInterval? {
        let parts = value.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":")
        guard parts.count == 2, let minutes = Double(parts[0]), let seconds = Double(parts[1]) else { return nil }
        return minutes * 60 + seconds
    }
}

@MainActor
final class KugouAccessibilityBridge {
    private var progressEstimator = KugouProgressEstimator()

    var isTrusted: Bool { AXIsProcessTrusted() }

    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func snapshot(processIdentifier: pid_t) -> PlayerSnapshot {
        guard isTrusted else { return .init(availability: .permissionRequired, player: .kugou) }
        let application = AXUIElementCreateApplication(processIdentifier)
        var entries: [KugouAXTextEntry] = []
        var visited = 0
        // KuGou 3.3.2 is a Catalyst app; its persistent playback bar is exposed
        // under the application element rather than the AXWindow subtree.
        collectText(from: application, entries: &entries, visited: &visited)
        guard let playback = KugouAXSnapshotParser.parse(entries) else {
            return .init(availability: .connecting("正在等待酷狗播放信息…"), player: .kugou)
        }

        let track = TrackIdentity(title: playback.title, artist: playback.artist, duration: playback.duration, player: .kugou)
        let estimate = progressEstimator.update(trackKey: track.normalizedKey, rawProgress: playback.progress, now: Date())
        return .init(availability: .ready, track: track, progress: estimate.progress, isPlaying: estimate.isPlaying, player: .kugou)
    }

    func perform(_ command: PlayerCommand, processIdentifier: pid_t) -> Bool {
        guard isTrusted else { requestPermission(); return false }
        let title: String
        switch command {
        case .previous: title = "上一曲"
        case .playPause: title = "播放/暂停"
        case .next: title = "下一曲"
        }
        let application = AXUIElementCreateApplication(processIdentifier)
        guard let menuBarValue = attribute(application, kAXMenuBarAttribute),
              let item = findMenuItem(title: title, in: menuBarValue as! AXUIElement, visited: 0) else { return false }
        return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
    }

    private func collectText(from element: AXUIElement, entries: inout [KugouAXTextEntry], visited: inout Int) {
        guard visited < 30_000 else { return }
        visited += 1
        if attribute(element, kAXRoleAttribute) as? String == kAXStaticTextRole as String,
           let rawPosition = attribute(element, kAXPositionAttribute) {
            let candidates = [kAXValueAttribute, kAXDescriptionAttribute, kAXTitleAttribute]
                .compactMap { attribute(element, $0) as? String }
            guard let value = candidates.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
                if let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] {
                    for child in children { collectText(from: child, entries: &entries, visited: &visited) }
                }
                return
            }
            var position = CGPoint.zero
            if AXValueGetValue(rawPosition as! AXValue, .cgPoint, &position) { entries.append(.init(value: value, position: position)) }
        }
        if let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] {
            for child in children { collectText(from: child, entries: &entries, visited: &visited) }
        }
    }

    private func findMenuItem(title: String, in element: AXUIElement, visited: Int) -> AXUIElement? {
        guard visited < 1_000 else { return nil }
        if attribute(element, kAXRoleAttribute) as? String == kAXMenuItemRole as String,
           attribute(element, kAXTitleAttribute) as? String == title { return element }
        guard let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] else { return nil }
        for child in children {
            if let result = findMenuItem(title: title, in: child, visited: visited + 1) { return result }
        }
        return nil
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
}

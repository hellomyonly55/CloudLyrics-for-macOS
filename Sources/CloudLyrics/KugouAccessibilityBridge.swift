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

private struct KugouAXMatch {
    var state: KugouAXPlaybackState
    var titleIndex: Int
    var progressIndex: Int
    var durationIndex: Int
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
        match(entries)?.state
    }

    fileprivate static func match(_ entries: [KugouAXTextEntry]) -> KugouAXMatch? {
        guard let durationIndex = entries.lastIndex(where: { matches(durationRegex, $0.value) }) else { return nil }
        let durationEntry = entries[durationIndex]
        guard let progressIndex = entries.indices.filter({ matches(elapsedRegex, entries[$0].value) })
                .min(by: { abs(entries[$0].position.y - durationEntry.position.y) < abs(entries[$1].position.y - durationEntry.position.y) }),
              let duration = parseClock(durationEntry.value.replacingOccurrences(of: "/", with: "")),
              let progress = parseClock(entries[progressIndex].value) else { return nil }
        let titleCandidates = entries.indices.filter {
            entries[$0].value.contains(" - ") && abs(entries[$0].position.y - entries[progressIndex].position.y) < 20
        }
        guard let titleIndex = titleCandidates.min(by: {
            abs(entries[$0].position.x - entries[progressIndex].position.x) < abs(entries[$1].position.x - entries[progressIndex].position.x)
        }) else { return nil }
        let combined = entries[titleIndex].value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let separator = combined.range(of: " - ", options: .backwards) else { return nil }
        let title = combined[..<separator.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = combined[separator.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !artist.isEmpty else { return nil }
        return .init(
            state: .init(title: title, artist: artist, progress: progress, duration: duration),
            titleIndex: titleIndex,
            progressIndex: progressIndex,
            durationIndex: durationIndex
        )
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

struct KugouAccessibilityLocator<Node: Hashable> {
    struct Candidate {
        var entry: KugouAXTextEntry
        var node: Node
    }

    private var cachedNodes: (title: Node, progress: Node, duration: Node)?

    mutating func resolve(
        read: (Node) -> KugouAXTextEntry?,
        scan: () -> [Candidate]
    ) -> KugouAXPlaybackState? {
        if let cachedNodes {
            let nodes = [cachedNodes.title, cachedNodes.progress, cachedNodes.duration]
            let entries = nodes.compactMap(read)
            if entries.count == nodes.count, let match = KugouAXSnapshotParser.match(entries) {
                return match.state
            }
            self.cachedNodes = nil
        }

        let candidates = scan()
        let entries = candidates.map(\.entry)
        guard let match = KugouAXSnapshotParser.match(entries) else { return nil }
        cachedNodes = (
            candidates[match.titleIndex].node,
            candidates[match.progressIndex].node,
            candidates[match.durationIndex].node
        )
        return match.state
    }

    mutating func reset() { cachedNodes = nil }
}

private struct KugouAXNode: Hashable, @unchecked Sendable {
    let element: AXUIElement

    static func == (lhs: Self, rhs: Self) -> Bool { CFEqual(lhs.element, rhs.element) }
    func hash(into hasher: inout Hasher) { hasher.combine(CFHash(element)) }
}

private final class KugouAXScanner: @unchecked Sendable {
    private let queue = DispatchQueue(label: "io.github.hellomyonly55.CloudLyrics.kugou-accessibility", qos: .userInitiated)
    private var locator = KugouAccessibilityLocator<KugouAXNode>()

    func request(processIdentifier: pid_t, completion: @escaping @Sendable (KugouAXPlaybackState?) -> Void) {
        queue.async { [self] in
            let application = KugouAXNode(element: AXUIElementCreateApplication(processIdentifier))
            let result = locator.resolve(
                read: { self.textEntry(for: $0) },
                scan: { self.collectCandidates(from: application) }
            )
            completion(result)
        }
    }

    func reset() {
        queue.async { [self] in locator.reset() }
    }

    private func collectCandidates(from application: KugouAXNode) -> [KugouAccessibilityLocator<KugouAXNode>.Candidate] {
        var candidates: [KugouAccessibilityLocator<KugouAXNode>.Candidate] = []
        var visited = 0
        collectText(from: application, candidates: &candidates, visited: &visited)
        return candidates
    }

    private func collectText(
        from node: KugouAXNode,
        candidates: inout [KugouAccessibilityLocator<KugouAXNode>.Candidate],
        visited: inout Int
    ) {
        guard visited < 30_000 else { return }
        visited += 1
        if let entry = textEntry(for: node) { candidates.append(.init(entry: entry, node: node)) }
        if let children = attribute(node.element, kAXChildrenAttribute) as? [AXUIElement] {
            for child in children.reversed() {
                collectText(from: .init(element: child), candidates: &candidates, visited: &visited)
            }
        }
    }

    private func textEntry(for node: KugouAXNode) -> KugouAXTextEntry? {
        guard attribute(node.element, kAXRoleAttribute) as? String == kAXStaticTextRole as String,
              let rawPosition = attribute(node.element, kAXPositionAttribute) else { return nil }
        let candidates = [kAXValueAttribute, kAXDescriptionAttribute, kAXTitleAttribute]
            .compactMap { attribute(node.element, $0) as? String }
        guard let value = candidates.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { return nil }
        var position = CGPoint.zero
        guard AXValueGetValue(rawPosition as! AXValue, .cgPoint, &position) else { return nil }
        return .init(value: value, position: position)
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
}

@MainActor
final class KugouAccessibilityBridge {
    private var progressEstimator = KugouProgressEstimator()
    private let scanner = KugouAXScanner()
    private var scanPending = false
    private var latestPlayback: KugouAXPlaybackState?
    private var processIdentifier: pid_t?

    var isTrusted: Bool { AXIsProcessTrusted() }

    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func snapshot(processIdentifier: pid_t) -> PlayerSnapshot {
        guard isTrusted else { return .init(availability: .permissionRequired, player: .kugou) }
        if self.processIdentifier != processIdentifier {
            self.processIdentifier = processIdentifier
            latestPlayback = nil
            progressEstimator = .init()
            scanner.reset()
        }
        requestUpdate(processIdentifier: processIdentifier)
        guard let playback = latestPlayback else {
            return .init(availability: .connecting("正在等待酷狗播放信息…"), player: .kugou)
        }

        let track = TrackIdentity(title: playback.title, artist: playback.artist, duration: playback.duration, player: .kugou)
        let estimate = progressEstimator.update(trackKey: track.normalizedKey, rawProgress: playback.progress, now: Date())
        return .init(availability: .ready, track: track, progress: estimate.progress, isPlaying: estimate.isPlaying, player: .kugou)
    }

    private func requestUpdate(processIdentifier: pid_t) {
        guard !scanPending else { return }
        scanPending = true
        scanner.request(processIdentifier: processIdentifier) { [weak self] playback in
            DispatchQueue.main.async {
                guard let self else { return }
                self.scanPending = false
                guard self.processIdentifier == processIdentifier else { return }
                self.latestPlayback = playback
            }
        }
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

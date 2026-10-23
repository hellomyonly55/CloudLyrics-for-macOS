import ApplicationServices
import CommonCrypto
import Foundation

struct NetEaseLastPlayingState: Decodable, Equatable, Sendable {
    var current: TimeInterval
    var resourceDuration: TimeInterval?
    var resourceID: String
    var trackID: String?

    private enum CodingKeys: String, CodingKey {
        case current, resourceDuration, resourceID = "resourceId", trackID = "trackId"
    }

    var songID: String? {
        if !resourceID.isEmpty { return resourceID }
        guard let trackID, !trackID.isEmpty else { return nil }
        return trackID
    }
}

struct NetEaseProgressEstimator {
    private var songID: String?
    private var progress: TimeInterval = 0
    private var exactProgress: TimeInterval = 0
    private var observedAt: Date?
    private var wasPlaying = false
    private var pendingBackwardProgress: TimeInterval?

    mutating func update(
        songID: String,
        duration: TimeInterval?,
        exactProgress: TimeInterval,
        isPlaying: Bool,
        now: Date
    ) -> TimeInterval {
        let incomingProgress = max(0, exactProgress)
        if self.songID != songID {
            self.songID = songID
            self.exactProgress = incomingProgress
            progress = incomingProgress
            observedAt = now
            wasPlaying = isPlaying
            pendingBackwardProgress = nil
            return normalized(progress, duration: duration)
        }

        let exactChanged = abs(self.exactProgress - incomingProgress) > 0.001
        if exactChanged {
            let movedBackward = incomingProgress < self.exactProgress
            if movedBackward, isPlaying {
                if let pendingBackwardProgress,
                   abs(pendingBackwardProgress - incomingProgress) > 0.001 {
                    // A second advancing native value in the lower range
                    // confirms a real seek or same-track repeat.
                    self.exactProgress = incomingProgress
                    self.pendingBackwardProgress = nil
                    progress = incomingProgress
                    observedAt = now
                    wasPlaying = true
                    return normalized(progress, duration: duration)
                }

                // LevelDB compaction can expose one old lastPlaying record for
                // a single scan. Keep advancing from the last trusted value
                // until another distinct lower value confirms the jump.
                if pendingBackwardProgress == nil {
                    pendingBackwardProgress = incomingProgress
                }
                if wasPlaying, let observedAt {
                    progress += max(0, now.timeIntervalSince(observedAt))
                }
                self.observedAt = now
                wasPlaying = true
                return normalized(progress, duration: duration)
            }

            pendingBackwardProgress = nil
            self.exactProgress = incomingProgress
            if movedBackward {
                // A confirmed lower native value means a seek or same-track
                // repeat and is authoritative even while paused.
                progress = incomingProgress
            } else if !isPlaying {
                // A delayed forward write can arrive after audio has stopped.
                // Freeze at the furthest trusted point instead of snapping back
                // from interpolation to the older on-disk value.
                progress = max(progress, incomingProgress)
            } else {
                // Include the time since the last observation before applying
                // a delayed native tick, so an in-between lyric boundary does
                // not rewind when the next player sample arrives.
                let advanced = wasPlaying ? max(0, observedAt.map { now.timeIntervalSince($0) } ?? 0) : 0
                progress = max(progress + advanced, incomingProgress)
            }
            observedAt = now
            wasPlaying = isPlaying
            return normalized(progress, duration: duration)
        }

        pendingBackwardProgress = nil

        if wasPlaying, !isPlaying {
            // CoreAudio stopping is authoritative for motion, but lastPlaying
            // may lag several seconds. Freeze; never rewind to that stale value.
            progress = max(progress, incomingProgress)
            observedAt = now
            wasPlaying = false
            return normalized(progress, duration: duration)
        }

        if wasPlaying, isPlaying, let observedAt {
            progress += max(0, now.timeIntervalSince(observedAt))
        }
        self.observedAt = now
        wasPlaying = isPlaying
        progress = normalized(progress, duration: duration)
        return progress
    }

    private func normalized(_ value: TimeInterval, duration: TimeInterval?) -> TimeInterval {
        guard let duration, duration > 0 else { return value }
        return min(value, duration)
    }
}

struct NetEasePlaybackActivityResolver {
    static let staleInterval: TimeInterval = 6.5

    private var songID: String?
    private var exactProgress: TimeInterval?
    private var lastExactChangeAt: Date?

    mutating func resolve(
        songID: String,
        exactProgress: TimeInterval,
        audible: Bool?,
        now: Date
    ) -> Bool {
        if self.songID != songID || self.exactProgress.map({ abs($0 - exactProgress) > 0.001 }) != false {
            self.songID = songID
            self.exactProgress = exactProgress
            lastExactChangeAt = now
        }
        if let audible { return audible }
        guard let lastExactChangeAt else { return false }
        return now.timeIntervalSince(lastExactChangeAt) <= Self.staleInterval
    }
}

enum NetEaseLastPlayingDecoder {
    private static let marker = Array("lastPlaying".utf8)
    private static let key = Array(")(13daqP@ssw0rd~".utf8)

    static func decode(base64: String) -> NetEaseLastPlayingState? {
        guard let encrypted = Data(base64Encoded: base64),
              !encrypted.isEmpty,
              encrypted.count.isMultiple(of: kCCBlockSizeAES128),
              let decrypted = decrypt(encrypted),
              let state = try? JSONDecoder().decode(NetEaseLastPlayingState.self, from: decrypted),
              state.songID != nil,
              state.current.isFinite,
              state.current >= 0 else { return nil }
        return state
    }

    static func states(in data: Data) -> [(offset: Int, state: NetEaseLastPlayingState)] {
        let bytes = Array(data)
        guard bytes.count >= marker.count else { return [] }
        var results: [(Int, NetEaseLastPlayingState)] = []
        var markerStart = 0

        while markerStart <= bytes.count - marker.count {
            guard let found = find(marker, in: bytes, from: markerStart) else { break }
            let valueStart = found + marker.count
            let valueEnd = min(bytes.count, valueStart + 1_024)
            var cursor = valueStart

            while cursor < valueEnd {
                while cursor < valueEnd, !isBase64Byte(bytes[cursor]) { cursor += 1 }
                let runStart = cursor
                while cursor < valueEnd, isBase64Byte(bytes[cursor]), bytes[cursor] != 61 { cursor += 1 }
                var runEnd = cursor
                if cursor < valueEnd, bytes[cursor] == 61 {
                    runEnd += 1
                    cursor += 1
                    if cursor < valueEnd, bytes[cursor] == 61 {
                        runEnd += 1
                        cursor += 1
                    }
                }

                if runEnd - runStart >= 64 {
                    let maximumPrefix = min(16, runEnd - runStart - 64)
                    let maximumSuffix = min(16, runEnd - runStart - 64)
                    candidateLoop: for prefix in 0...maximumPrefix {
                        for suffix in 0...maximumSuffix {
                            let start = runStart + prefix
                            let end = runEnd - suffix
                            let length = end - start
                            guard length >= 64, length.isMultiple(of: 4) else { continue }
                            let encoded = String(decoding: bytes[start..<end], as: UTF8.self)
                            if let state = decode(base64: encoded) {
                                results.append((start, state))
                                break candidateLoop
                            }
                        }
                    }
                }

                if cursor == runStart { cursor += 1 }
            }
            markerStart = found + marker.count
        }
        return results
    }

    private static func decrypt(_ encrypted: Data) -> Data? {
        let outputCapacity = encrypted.count + kCCBlockSizeAES128
        var output = Data(count: outputCapacity)
        var outputLength = 0
        let status = output.withUnsafeMutableBytes { outputBytes in
            encrypted.withUnsafeBytes { encryptedBytes in
                key.withUnsafeBytes { keyBytes in
                    CCCrypt(
                        CCOperation(kCCDecrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionPKCS7Padding | kCCOptionECBMode),
                        keyBytes.baseAddress,
                        key.count,
                        nil,
                        encryptedBytes.baseAddress,
                        encrypted.count,
                        outputBytes.baseAddress,
                        outputCapacity,
                        &outputLength
                    )
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        output.removeSubrange(outputLength..<output.count)
        return output
    }

    private static func find(_ needle: [UInt8], in bytes: [UInt8], from start: Int) -> Int? {
        guard start <= bytes.count - needle.count else { return nil }
        for index in start...(bytes.count - needle.count) where bytes[index] == needle[0] {
            if bytes[index..<(index + needle.count)].elementsEqual(needle) { return index }
        }
        return nil
    }

    private static func isBase64Byte(_ byte: UInt8) -> Bool {
        (65...90).contains(byte) || (97...122).contains(byte) ||
            (48...57).contains(byte) || byte == 43 || byte == 47 || byte == 61
    }
}

private struct NetEaseLocalPlayback: @unchecked Sendable {
    var track: TrackIdentity
    var exactProgress: TimeInterval
}

struct NetEaseLastPlayingStateCache {
    private(set) var state: NetEaseLastPlayingState?

    mutating func observeLog(_ candidate: NetEaseLastPlayingState) -> NetEaseLastPlayingState {
        state = candidate
        return candidate
    }

    mutating func bootstrapFromTable(_ candidate: NetEaseLastPlayingState) -> NetEaseLastPlayingState {
        guard state == nil else { return state! }
        state = candidate
        return candidate
    }

    mutating func reset() { state = nil }
}

enum NetEaseLocalReadFailure {
    static func message(for error: Error) -> String? {
        let error = error as NSError
        if error.domain == NSCocoaErrorDomain, error.code == NSFileReadNoSuchFileError { return nil }
        if (error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoPermissionError) ||
            (error.domain == NSPOSIXErrorDomain && [1, 13].contains(error.code)) {
            return "无法读取网易云播放数据：请在系统设置 → 隐私与安全性 → 完全磁盘访问权限中允许 CloudLyrics，然后退出并重新打开。辅助功能授权不包含此权限。"
        }
        return "网易云播放数据读取失败：\(error.localizedDescription)"
    }
}

private final class NetEaseLastPlayingReader: @unchecked Sendable {
    private struct Signature: Equatable {
        var size: Int
        var modifiedAt: Date
    }

    private let directoryURL: URL
    private var signatures: [String: Signature] = [:]
    private var cache = NetEaseLastPlayingStateCache()
    private(set) var failure: String?

    init(containerURL: URL) {
        directoryURL = containerURL.appendingPathComponent(
            "Documents/storage/CEFCache/Local Storage/leveldb",
            isDirectory: true
        )
    }

    func read() -> NetEaseLastPlayingState? {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        failure = nil
        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles]
            )
        } catch {
            failure = NetEaseLocalReadFailure.message(for: error)
            return nil
        }

        var changedLogs: [(URL, Signature)] = []
        var changedTables: [(URL, Signature)] = []
        for url in urls {
            let extensionName = url.pathExtension.lowercased()
            guard extensionName == "log" || extensionName == "ldb",
                  let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true,
                  let size = values.fileSize,
                  let modifiedAt = values.contentModificationDate else { continue }
            let signature = Signature(size: size, modifiedAt: modifiedAt)
            guard signatures[url.path] != signature else { continue }
            if extensionName == "log" {
                changedLogs.append((url, signature))
            } else {
                changedTables.append((url, signature))
            }
        }

        changedLogs.sort { newer($0, than: $1) }
        for (url, signature) in changedLogs {
            guard let data = tail(of: url, size: signature.size) else { continue }
            signatures[url.path] = signature
            if let state = NetEaseLastPlayingDecoder.states(in: data).last?.state {
                return cache.observeLog(state)
            }
        }

        // SSTables are a bootstrap fallback. During live playback, LevelDB
        // compaction may create a table that still contains older revisions of
        // lastPlaying; it must not replace a state already observed from the
        // append-only log.
        guard cache.state == nil else { return cache.state }

        changedTables.sort { newer($0, than: $1) }
        for (url, signature) in changedTables {
            let data: Data
            do { data = try Data(contentsOf: url, options: .mappedIfSafe) }
            catch { failure = NetEaseLocalReadFailure.message(for: error); continue }
            signatures[url.path] = signature
            if let state = NetEaseLastPlayingDecoder.states(in: data).first?.state {
                return cache.bootstrapFromTable(state)
            }
        }
        return cache.state
    }

    func reset() {
        signatures.removeAll(keepingCapacity: true)
        cache.reset()
    }

    private func tail(of url: URL, size: Int) -> Data? {
        let handle: FileHandle
        do { handle = try FileHandle(forReadingFrom: url) }
        catch { failure = NetEaseLocalReadFailure.message(for: error); return nil }
        defer { try? handle.close() }
        let maximumBytes = 128 * 1_024
        let start = max(0, size - maximumBytes)
        do {
            try handle.seek(toOffset: UInt64(start))
            return try handle.readToEnd()
        } catch {
            failure = NetEaseLocalReadFailure.message(for: error)
            return nil
        }
    }

    private func newer(_ lhs: (URL, Signature), than rhs: (URL, Signature)) -> Bool {
        if lhs.1.modifiedAt != rhs.1.modifiedAt { return lhs.1.modifiedAt > rhs.1.modifiedAt }
        return lhs.0.lastPathComponent > rhs.0.lastPathComponent
    }
}

private final class NetEaseLocalStateScanner: @unchecked Sendable {
    private struct PlayingList: Decodable {
        struct Entry: Decodable {
            struct Track: Decodable {
                struct Artist: Decodable { var name: String }
                var name: String
                var duration: Double?
                var artists: [Artist]?
            }

            var id: String
            var track: Track?
        }

        var list: [Entry]
    }

    private let queue = DispatchQueue(label: "io.github.hellomyonly55.CloudLyrics.netease-local-state", qos: .utility)
    private let containerURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Containers/com.netease.163music/Data", isDirectory: true)
    private lazy var stateReader = NetEaseLastPlayingReader(containerURL: containerURL)
    private var cachedTracks: [String: TrackIdentity] = [:]

    func request(
        completion: @escaping @Sendable (NetEaseLocalPlayback?, String?) -> Void
    ) {
        queue.async { [self] in
            let playback = scan()
            completion(playback, stateReader.failure)
        }
    }

    func reset() {
        queue.async { [self] in
            cachedTracks.removeAll(keepingCapacity: true)
            stateReader.reset()
        }
    }

    private func scan() -> NetEaseLocalPlayback? {
        guard let state = stateReader.read() else { return nil }
        guard let songID = state.songID else { return nil }
        let resolvedTrack = cachedTracks[songID] ?? track(songID: songID)
        if let resolvedTrack { cachedTracks[songID] = resolvedTrack }
        var track = resolvedTrack ?? TrackIdentity(
            title: "正在获取歌曲信息…",
            artist: "网易云音乐",
            duration: state.resourceDuration,
            sourceID: songID,
            player: .netease
        )
        if let duration = state.resourceDuration, duration > 0 { track.duration = duration }
        return NetEaseLocalPlayback(
            track: track,
            exactProgress: state.current
        )
    }

    private func track(songID: String) -> TrackIdentity? {
        let url = containerURL
            .appendingPathComponent("Documents/storage/file_storage/webdata/file/playingList")
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let playingList = try? JSONDecoder().decode(PlayingList.self, from: data),
              let entry = playingList.list.first(where: { $0.id == songID }),
              let value = entry.track else { return nil }
        let artist = value.artists?.map(\.name).joined(separator: " / ") ?? "未知歌手"
        return .init(
            title: value.name,
            artist: artist,
            duration: value.duration.map { $0 / 1000 },
            sourceID: songID,
            player: .netease
        )
    }

}

@MainActor
final class NetEaseLocalPlaybackBridge {
    static let scanInterval: TimeInterval = 0.5

    private let scanner = NetEaseLocalStateScanner()
    private var progressEstimator = NetEaseProgressEstimator()
    private var activityResolver = NetEasePlaybackActivityResolver()
    private var processIdentifier: pid_t?
    private var latestPlayback: NetEaseLocalPlayback?
    private var readFailure: String?
    private var scanPending = false
    private var nextScanAt = Date.distantPast

    func snapshot(
        processIdentifier: pid_t,
        audible: Bool?,
        now: Date = Date()
    ) -> PlayerSnapshot {
        if self.processIdentifier != processIdentifier {
            self.processIdentifier = processIdentifier
            latestPlayback = nil
            readFailure = nil
            progressEstimator = .init()
            activityResolver = .init()
            nextScanAt = .distantPast
            scanner.reset()
        }
        requestUpdate(processIdentifier: processIdentifier, now: now)
        if let readFailure {
            return .init(availability: .incompatible(readFailure), player: .netease)
        }
        guard let playback = latestPlayback, let songID = playback.track.sourceID else {
            return .init(availability: .connecting("正在等待网易云播放信息…"), player: .netease)
        }
        let isPlaying = activityResolver.resolve(
            songID: songID,
            exactProgress: playback.exactProgress,
            audible: audible,
            now: now
        )
        let progress = progressEstimator.update(
            songID: songID,
            duration: playback.track.duration,
            exactProgress: playback.exactProgress,
            isPlaying: isPlaying,
            now: now
        )
        return .init(
            availability: .ready,
            track: playback.track,
            progress: progress,
            isPlaying: isPlaying,
            player: .netease
        )
    }

    func reset() {
        guard processIdentifier != nil || latestPlayback != nil || scanPending else { return }
        processIdentifier = nil
        latestPlayback = nil
        readFailure = nil
        progressEstimator = .init()
        activityResolver = .init()
        scanPending = false
        nextScanAt = .distantPast
        scanner.reset()
    }

    private func requestUpdate(processIdentifier: pid_t, now: Date) {
        guard !scanPending, now >= nextScanAt else { return }
        scanPending = true
        nextScanAt = now.addingTimeInterval(Self.scanInterval)
        scanner.request { [weak self] playback, failure in
            DispatchQueue.main.async {
                guard let self else { return }
                self.scanPending = false
                guard self.processIdentifier == processIdentifier else { return }
                self.readFailure = failure
                // Keep the last observation through a brief LevelDB rotation
                // while NetEase switches or repeats a track.
                if let playback { self.latestPlayback = playback }
            }
        }
    }
}

@MainActor
final class NetEaseAccessibilityCommandBridge {
    var isTrusted: Bool { AXIsProcessTrusted() }

    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func perform(_ command: PlayerCommand, processIdentifier: pid_t) -> Bool {
        guard isTrusted else { requestPermission(); return false }
        let titles = Self.menuTitles(for: command)
        let application = AXUIElementCreateApplication(processIdentifier)
        guard let menuBar = elementAttribute(application, kAXMenuBarAttribute),
              let item = findMenuItem(titles: titles, in: menuBar, visited: 0) else { return false }
        return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
    }

    static func menuTitles(for command: PlayerCommand) -> Set<String> {
        switch command {
        case .previous: ["上一个", "上一首", "上一曲", "Previous", "Previous Track"]
        case .playPause: ["播放", "暂停", "播放/暂停", "Play", "Pause", "Play/Pause"]
        case .next: ["下一个", "下一首", "下一曲", "Next", "Next Track"]
        }
    }

    func diagnosticSummary(processIdentifier: pid_t) -> String {
        guard isTrusted else { return "AX_TRUSTED=false" }
        let application = AXUIElementCreateApplication(processIdentifier)
        guard let menuBar = elementAttribute(application, kAXMenuBarAttribute) else { return "AX_TRUSTED=true MENU_UNAVAILABLE" }
        return (["AX_TRUSTED=true"] + [PlayerCommand.previous, .playPause, .next].map { command in
            guard let item = findMenuItem(titles: Self.menuTitles(for: command), in: menuBar, visited: 0) else {
                return "\(command)=missing"
            }
            let enabled = attribute(item, kAXEnabledAttribute) as? Bool ?? false
            return "\(command)=\(attribute(item, kAXTitleAttribute) as? String ?? "unknown"),enabled=\(enabled)"
        }).joined(separator: "\n")
    }

    private func findMenuItem(titles: Set<String>, in element: AXUIElement, visited: Int) -> AXUIElement? {
        guard visited < 1_000 else { return nil }
        if attribute(element, kAXRoleAttribute) as? String == kAXMenuItemRole as String,
           let title = attribute(element, kAXTitleAttribute) as? String,
           titles.contains(title) { return element }
        guard let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] else { return nil }
        for child in children {
            if let result = findMenuItem(titles: titles, in: child, visited: visited + 1) { return result }
        }
        return nil
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private func elementAttribute(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attribute(element, name),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
}

import AppKit
import Darwin
import Foundation

enum PlayerBundleIdentifiers {
    static let netease = "com.netease.163music"
    static let kugou = "com.kugou.mac.Music"
}

struct SystemNowPlayingState: Equatable {
    var processIdentifier: pid_t
    var title: String
    var artist: String
    var duration: TimeInterval?
    var elapsed: TimeInterval
    var rate: Double
    var timestamp: Date?
    var sourceID: String?
    var observedAt = Date()

    var bundleIdentifier: String? {
        NSRunningApplication(processIdentifier: processIdentifier)?.bundleIdentifier
    }

    var currentProgress: TimeInterval {
        let advanced = rate > 0 ? max(0, Date().timeIntervalSince(timestamp ?? observedAt)) * rate : 0
        return max(0, elapsed + advanced)
    }
}

@MainActor
final class MediaRemoteBridge {
    private typealias GetPID = @convention(c) (DispatchQueue, @escaping @convention(block) (Int32) -> Void) -> Void
    private typealias GetInfo = @convention(c) (DispatchQueue, @escaping @convention(block) (CFDictionary?) -> Void) -> Void
    private typealias SendCommand = @convention(c) (Int32, CFDictionary?) -> Bool
    private typealias RegisterNotifications = @convention(c) (DispatchQueue) -> Void
    private typealias SetWantsNotifications = @convention(c) (Bool) -> Void

    private let handle: UnsafeMutableRawPointer?
    private let getPID: GetPID?
    private let getInfo: GetInfo?
    private let sendCommand: SendCommand?
    private let registerNotifications: RegisterNotifications?
    private let setWantsNotifications: SetWantsNotifications?
    private var pending = false
    private var receivedPID: pid_t?
    private var receivedInfo: [String: Any]?
    private(set) var state: SystemNowPlayingState?
    private(set) var diagnosticSummary = "尚未请求系统播放信息"

    var isAvailable: Bool { getPID != nil && getInfo != nil && sendCommand != nil }

    init() {
        handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY | RTLD_LOCAL)
        if let handle,
           let pidSymbol = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationPID"),
           let infoSymbol = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo"),
           let commandSymbol = dlsym(handle, "MRMediaRemoteSendCommand") {
            getPID = unsafeBitCast(pidSymbol, to: GetPID.self)
            getInfo = unsafeBitCast(infoSymbol, to: GetInfo.self)
            sendCommand = unsafeBitCast(commandSymbol, to: SendCommand.self)
            registerNotifications = dlsym(handle, "MRMediaRemoteRegisterForNowPlayingNotifications").map {
                unsafeBitCast($0, to: RegisterNotifications.self)
            }
            setWantsNotifications = dlsym(handle, "MRMediaRemoteSetWantsNowPlayingNotifications").map {
                unsafeBitCast($0, to: SetWantsNotifications.self)
            }
        } else {
            getPID = nil; getInfo = nil; sendCommand = nil
            registerNotifications = nil; setWantsNotifications = nil
        }
        setWantsNotifications?(true)
        registerNotifications?(.main)
    }

    deinit {
        setWantsNotifications?(false)
        if let handle { dlclose(handle) }
    }

    func update() {
        guard !pending, let getPID, let getInfo else { return }
        pending = true
        receivedPID = nil
        receivedInfo = nil
        getPID(.main) { [weak self] pid in
            Task { @MainActor in
                self?.receivedPID = pid_t(pid)
                self?.finishUpdateIfReady()
            }
        }
        getInfo(.main) { [weak self] dictionary in
            let info = dictionary as? [String: Any] ?? [:]
            Task { @MainActor in
                self?.receivedInfo = info
                self?.finishUpdateIfReady()
            }
        }
    }

    func perform(_ command: PlayerCommand, expectedBundleIdentifier: String) -> Bool {
        guard state?.bundleIdentifier == expectedBundleIdentifier, let sendCommand else { return false }
        let value: Int32
        switch command {
        case .playPause: value = 2
        case .next: value = 4
        case .previous: value = 5
        }
        return sendCommand(value, nil)
    }

    private func finishUpdateIfReady() {
        guard let pid = receivedPID, let info = receivedInfo else { return }
        pending = false
        diagnosticSummary = "pid=\(pid), keys=\(info.keys.sorted().joined(separator: ","))"
        guard pid > 0,
              let title = string(info, "kMRMediaRemoteNowPlayingInfoTitle"),
              !title.isEmpty else { return }
        state = .init(
            processIdentifier: pid,
            title: title,
            artist: string(info, "kMRMediaRemoteNowPlayingInfoArtist") ?? "未知歌手",
            duration: number(info, "kMRMediaRemoteNowPlayingInfoDuration"),
            elapsed: number(info, "kMRMediaRemoteNowPlayingInfoElapsedTime") ?? 0,
            rate: number(info, "kMRMediaRemoteNowPlayingInfoPlaybackRate") ?? 0,
            timestamp: info["kMRMediaRemoteNowPlayingInfoTimestamp"] as? Date,
            sourceID: string(info, "kMRMediaRemoteNowPlayingInfoUniqueIdentifier")
        )
    }

    private func string(_ values: [String: Any], _ key: String) -> String? { values[key] as? String }
    private func number(_ values: [String: Any], _ key: String) -> Double? { (values[key] as? NSNumber)?.doubleValue }
}

@MainActor
final class KugouPlayerAdapter: PlayerAdapter {
    static let bundleIdentifier = PlayerBundleIdentifiers.kugou
    let kind: PlayerKind? = .kugou
    let bridge: MediaRemoteBridge
    private let accessibility: KugouAccessibilityBridge
    private var lastSnapshot: PlayerSnapshot?

    init(bridge: MediaRemoteBridge, accessibility: KugouAccessibilityBridge? = nil) {
        self.bridge = bridge
        self.accessibility = accessibility ?? KugouAccessibilityBridge()
    }

    var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleIdentifier).isEmpty }

    func snapshot() -> PlayerSnapshot {
        bridge.update()
        guard isRunning else { lastSnapshot = nil; return .init(availability: .notRunning, player: .kugou) }
        guard bridge.isAvailable else {
            return .init(availability: .incompatible("当前 macOS 无法访问系统播放信息"), player: .kugou)
        }
        if let state = bridge.state, state.bundleIdentifier == Self.bundleIdentifier {
            let track = TrackIdentity(
                title: state.title,
                artist: state.artist,
                duration: state.duration,
                sourceID: state.sourceID,
                player: .kugou
            )
            let snapshot = PlayerSnapshot(
                availability: .ready,
                track: track,
                progress: state.currentProgress,
                isPlaying: state.rate > 0,
                player: .kugou
            )
            lastSnapshot = snapshot
            return snapshot
        }
        guard let process = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleIdentifier).first else {
            return .init(availability: .notRunning, player: .kugou)
        }
        let snapshot = accessibility.snapshot(processIdentifier: process.processIdentifier)
        if snapshot.track != nil { lastSnapshot = snapshot }
        return snapshot
    }

    func perform(_ command: PlayerCommand) throws {
        guard let process = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleIdentifier).first else { throw AXPlayerError.notRunning }
        if bridge.perform(command, expectedBundleIdentifier: Self.bundleIdentifier) { return }
        guard accessibility.perform(command, processIdentifier: process.processIdentifier) else { throw AXPlayerError.controlUnavailable }
    }

    func requestPermission() { accessibility.requestPermission() }
}

@MainActor
final class AutomaticPlayerAdapter: PlayerAdapter {
    static let netEaseBundleIdentifier = PlayerBundleIdentifiers.netease
    let kind: PlayerKind? = nil
    private let mediaRemote: MediaRemoteBridge
    private let netease: PlayerAdapter
    private let kugou: PlayerAdapter
    private let audioActivity: AudioPlaybackActivityProviding
    private var selected: PlayerAdapter?

    init(
        mediaRemote: MediaRemoteBridge? = nil,
        netease: PlayerAdapter? = nil,
        kugou: PlayerAdapter? = nil,
        audioActivity: AudioPlaybackActivityProviding? = nil
    ) {
        let bridge = mediaRemote ?? MediaRemoteBridge()
        self.mediaRemote = bridge
        self.netease = netease ?? NetEaseAXPlayerAdapter()
        self.kugou = kugou ?? KugouPlayerAdapter(bridge: bridge)
        self.audioActivity = audioActivity ?? CoreAudioPlaybackActivity()
    }

    var isRunning: Bool { netease.isRunning || kugou.isRunning }
    var diagnosticSummary: String { mediaRemote.diagnosticSummary }

    func snapshot() -> PlayerSnapshot {
        mediaRemote.update()
        let frontmostBundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        // A paused app can remain MediaRemote's owner after another player has
        // started through its own internal engine. Only treat MediaRemote as an
        // active signal while it reports a positive playback rate.
        let activeBundle = mediaRemote.state.flatMap { $0.rate > 0 ? $0.bundleIdentifier : nil }
        let neteaseAudible = netease.isRunning ? audioActivity.isRunningOutput(bundleIdentifier: PlayerBundleIdentifiers.netease) : false
        let kugouAudible = kugou.isRunning ? audioActivity.isRunningOutput(bundleIdentifier: PlayerBundleIdentifiers.kugou) : false
        let shouldProbeNetEase = netease.isRunning && (
            selected?.kind == .netease ||
            neteaseAudible == true ||
            frontmostBundle == PlayerBundleIdentifiers.netease ||
            activeBundle == PlayerBundleIdentifiers.netease
        )
        let neteaseProbe = shouldProbeNetEase ? netease.snapshot() : nil
        let kugouProbe = kugou.isRunning ? kugou.snapshot() : nil
        let choice = AutomaticPlayerSelection.choose(
            activeBundleIdentifier: activeBundle,
            frontmostBundleIdentifier: frontmostBundle,
            previous: selected?.kind,
            neteaseRunning: netease.isRunning,
            kugouRunning: kugou.isRunning,
            neteaseAudible: neteaseAudible,
            kugouAudible: kugouAudible,
            neteasePlaying: neteaseProbe?.isPlaying == true,
            kugouPlaying: kugouProbe?.isPlaying == true
        )
        switch choice {
        case .netease: selected = netease
        case .kugou: selected = kugou
        case nil: selected = nil
        }
        guard let selected else {
            return .init(availability: .notRunning)
        }
        if selected.kind == .netease, let neteaseProbe { return neteaseProbe }
        if selected.kind == .kugou, let kugouProbe { return kugouProbe }
        return selected.snapshot()
    }

    func perform(_ command: PlayerCommand) throws {
        guard let selected else { throw AXPlayerError.notRunning }
        try selected.perform(command)
    }

    func requestPermission() { selected?.requestPermission() }
}

enum AutomaticPlayerSelection {
    static func choose(
        activeBundleIdentifier: String?,
        frontmostBundleIdentifier: String? = nil,
        previous: PlayerKind?,
        neteaseRunning: Bool,
        kugouRunning: Bool,
        neteaseAudible: Bool? = nil,
        kugouAudible: Bool? = nil,
        neteasePlaying: Bool = false,
        kugouPlaying: Bool = false
    ) -> PlayerKind? {
        // Actual audio output wins over window focus and stale MediaRemote
        // ownership, allowing a background player to drive the lyrics.
        if neteaseAudible == true, kugouAudible != true, neteaseRunning { return .netease }
        if kugouAudible == true, neteaseAudible != true, kugouRunning { return .kugou }
        if activeBundleIdentifier == PlayerBundleIdentifiers.kugou, kugouRunning { return .kugou }
        if activeBundleIdentifier == PlayerBundleIdentifiers.netease, neteaseRunning { return .netease }
        if neteasePlaying, !kugouPlaying { return .netease }
        if kugouPlaying { return .kugou }
        if neteasePlaying { return .netease }
        // Focus is only a fallback when neither process has measurable audio.
        if frontmostBundleIdentifier == PlayerBundleIdentifiers.netease, neteaseRunning { return .netease }
        if frontmostBundleIdentifier == PlayerBundleIdentifiers.kugou, kugouRunning { return .kugou }
        if previous == .kugou, kugouRunning { return .kugou }
        if previous == .netease, neteaseRunning { return .netease }
        if kugouRunning, !neteaseRunning { return .kugou }
        if neteaseRunning, !kugouRunning { return .netease }
        if kugouRunning { return .kugou }
        return nil
    }
}

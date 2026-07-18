import AppKit
import Darwin
import Foundation

enum PlayerBundleIdentifiers {
    static let netease = "com.netease.163music"
    static let kugou = "com.kugou.mac.Music"
}

struct PlayerProcessState: Equatable {
    private(set) var identifiersByBundle: [String: Set<pid_t>] = [:]

    mutating func applicationLaunched(bundleIdentifier: String, processIdentifier: pid_t) {
        identifiersByBundle[bundleIdentifier, default: []].insert(processIdentifier)
    }

    mutating func applicationTerminated(bundleIdentifier: String, processIdentifier: pid_t) {
        identifiersByBundle[bundleIdentifier]?.remove(processIdentifier)
    }

    func identifiers(for bundleIdentifier: String) -> [pid_t] {
        Array(identifiersByBundle[bundleIdentifier] ?? []).sorted()
    }
}

@MainActor
final class PlayerApplicationRegistry {
    private let workspace: NSWorkspace
    private var state = PlayerProcessState()
    private var observers: [NSObjectProtocol] = []

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
        for bundleIdentifier in [PlayerBundleIdentifiers.netease, PlayerBundleIdentifiers.kugou] {
            for application in NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier) {
                state.applicationLaunched(bundleIdentifier: bundleIdentifier, processIdentifier: application.processIdentifier)
            }
        }
        let center = workspace.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            Task { @MainActor in self?.recordLaunch(application) }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            Task { @MainActor in self?.recordTermination(application) }
        })
    }

    deinit {
        for observer in observers { workspace.notificationCenter.removeObserver(observer) }
    }

    func processIdentifiers(for bundleIdentifier: String) -> [pid_t] { state.identifiers(for: bundleIdentifier) }

    func runningApplications(for bundleIdentifier: String) -> [NSRunningApplication] {
        processIdentifiers(for: bundleIdentifier).compactMap(NSRunningApplication.init(processIdentifier:))
    }

    private func recordLaunch(_ application: NSRunningApplication) {
        guard let bundleIdentifier = application.bundleIdentifier else { return }
        state.applicationLaunched(bundleIdentifier: bundleIdentifier, processIdentifier: application.processIdentifier)
    }

    private func recordTermination(_ application: NSRunningApplication) {
        guard let bundleIdentifier = application.bundleIdentifier else { return }
        state.applicationTerminated(bundleIdentifier: bundleIdentifier, processIdentifier: application.processIdentifier)
    }
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

struct MediaRemoteRefreshPolicy {
    var safetyInterval: TimeInterval = 0.5
    private var dirty = true
    private var lastRefresh: Date?

    init(safetyInterval: TimeInterval = 0.5) {
        self.safetyInterval = safetyInterval
    }

    mutating func markDirty() { dirty = true }

    mutating func shouldRefresh(at now: Date) -> Bool {
        guard dirty || lastRefresh == nil || now.timeIntervalSince(lastRefresh!) >= safetyInterval else { return false }
        dirty = false
        lastRefresh = now
        return true
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
    private var refreshPolicy = MediaRemoteRefreshPolicy()
    private var notificationObservers: [NSObjectProtocol] = []
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
        let notificationCenter = NotificationCenter.default
        let notificationNames = [
            "kMRMediaRemoteNowPlayingInfoDidChangeNotification",
            "kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
            "MRMediaRemoteNowPlayingInfoDidChangeNotification",
            "MRMediaRemoteNowPlayingApplicationDidChangeNotification"
        ]
        notificationObservers = notificationNames.map { value in
            notificationCenter.addObserver(forName: .init(value), object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refreshPolicy.markDirty() }
            }
        }
    }

    deinit {
        for observer in notificationObservers { NotificationCenter.default.removeObserver(observer) }
        setWantsNotifications?(false)
        if let handle { dlclose(handle) }
    }

    func update() {
        guard !pending, refreshPolicy.shouldRefresh(at: Date()), let getPID, let getInfo else { return }
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
struct KugouSnapshotRetention {
    private var lastValid: (snapshot: PlayerSnapshot, observedAt: Date)?

    mutating func resolve(candidate: PlayerSnapshot, audible: Bool?, now: Date = Date()) -> PlayerSnapshot {
        if candidate.track != nil {
            lastValid = (candidate, now)
            return candidate
        }
        guard case .connecting = candidate.availability, let lastValid else { return candidate }

        var retained = lastValid.snapshot
        retained.availability = .ready
        if audible == true {
            retained.progress = lastValid.snapshot.progress + max(0, now.timeIntervalSince(lastValid.observedAt))
            retained.isPlaying = true
        } else if audible == false {
            retained.isPlaying = false
        }
        return retained
    }

    mutating func reset() { lastValid = nil }
}

@MainActor
final class KugouPlayerAdapter: PlayerAdapter {
    static let bundleIdentifier = PlayerBundleIdentifiers.kugou
    let kind: PlayerKind? = .kugou
    let bridge: MediaRemoteBridge
    private let accessibility: KugouAccessibilityBridge
    private let audioActivity: AudioPlaybackActivityProviding
    private let applications: PlayerApplicationRegistry
    private var retention = KugouSnapshotRetention()

    init(
        bridge: MediaRemoteBridge,
        accessibility: KugouAccessibilityBridge? = nil,
        audioActivity: AudioPlaybackActivityProviding? = nil,
        applications: PlayerApplicationRegistry? = nil
    ) {
        self.bridge = bridge
        self.accessibility = accessibility ?? KugouAccessibilityBridge()
        self.audioActivity = audioActivity ?? CoreAudioPlaybackActivity()
        self.applications = applications ?? PlayerApplicationRegistry()
    }

    var isRunning: Bool { !applications.processIdentifiers(for: Self.bundleIdentifier).isEmpty }

    func snapshot() -> PlayerSnapshot {
        bridge.update()
        guard isRunning else { retention.reset(); return .init(availability: .notRunning, player: .kugou) }
        guard bridge.isAvailable else {
            return .init(availability: .incompatible("当前 macOS 无法访问系统播放信息"), player: .kugou)
        }
        let processIdentifiers = applications.processIdentifiers(for: Self.bundleIdentifier)
        let audible = audioActivity.isRunningOutput(bundleIdentifier: Self.bundleIdentifier, processIdentifiers: processIdentifiers)
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
            return retention.resolve(candidate: snapshot, audible: state.rate > 0 ? true : audible)
        }
        guard let processIdentifier = processIdentifiers.first else {
            return .init(availability: .notRunning, player: .kugou)
        }
        let snapshot = accessibility.snapshot(processIdentifier: processIdentifier)
        return retention.resolve(candidate: snapshot, audible: audible)
    }

    func perform(_ command: PlayerCommand) throws {
        guard let processIdentifier = applications.processIdentifiers(for: Self.bundleIdentifier).first else { throw AXPlayerError.notRunning }
        if bridge.perform(command, expectedBundleIdentifier: Self.bundleIdentifier) { return }
        guard accessibility.perform(command, processIdentifier: processIdentifier) else { throw AXPlayerError.controlUnavailable }
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
    private let applications: PlayerApplicationRegistry
    private var selected: PlayerAdapter?

    init(
        mediaRemote: MediaRemoteBridge? = nil,
        netease: PlayerAdapter? = nil,
        kugou: PlayerAdapter? = nil,
        audioActivity: AudioPlaybackActivityProviding? = nil
    ) {
        let bridge = mediaRemote ?? MediaRemoteBridge()
        let activity = audioActivity ?? CoreAudioPlaybackActivity()
        let registry = PlayerApplicationRegistry()
        self.mediaRemote = bridge
        self.netease = netease ?? NetEaseAXPlayerAdapter(applications: registry)
        self.kugou = kugou ?? KugouPlayerAdapter(bridge: bridge, audioActivity: activity, applications: registry)
        self.audioActivity = activity
        self.applications = registry
    }

    var isRunning: Bool { netease.isRunning || kugou.isRunning }
    var diagnosticSummary: String { mediaRemote.diagnosticSummary }

    func snapshot() -> PlayerSnapshot {
        mediaRemote.update()
        let neteaseProcessIdentifiers = applications.processIdentifiers(for: PlayerBundleIdentifiers.netease)
        let kugouProcessIdentifiers = applications.processIdentifiers(for: PlayerBundleIdentifiers.kugou)
        let neteaseRunning = netease.isRunning
        let kugouRunning = kugou.isRunning
        let frontmostBundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        // A paused app can remain MediaRemote's owner after another player has
        // started through its own internal engine. Only treat MediaRemote as an
        // active signal while it reports a positive playback rate.
        let activeBundle = mediaRemote.state.flatMap { $0.rate > 0 ? $0.bundleIdentifier : nil }
        let neteaseAudible = neteaseRunning ? audioActivity.isRunningOutput(bundleIdentifier: PlayerBundleIdentifiers.netease, processIdentifiers: neteaseProcessIdentifiers) : false
        let kugouAudible = kugouRunning ? audioActivity.isRunningOutput(bundleIdentifier: PlayerBundleIdentifiers.kugou, processIdentifiers: kugouProcessIdentifiers) : false
        let shouldProbeNetEase = neteaseRunning && (
            selected?.kind == .netease ||
            neteaseAudible == true ||
            frontmostBundle == PlayerBundleIdentifiers.netease ||
            activeBundle == PlayerBundleIdentifiers.netease
        )
        let neteaseProbe = shouldProbeNetEase ? netease.snapshot() : nil
        let kugouProbe = kugouRunning ? kugou.snapshot() : nil
        let choice = AutomaticPlayerSelection.choose(
            activeBundleIdentifier: activeBundle,
            frontmostBundleIdentifier: frontmostBundle,
            previous: selected?.kind,
            neteaseRunning: neteaseRunning,
            kugouRunning: kugouRunning,
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

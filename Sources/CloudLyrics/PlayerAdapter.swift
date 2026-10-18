import AppKit
import Foundation

enum PlayerAvailability: Equatable {
    case ready, permissionRequired, notRunning, connecting(String), incompatible(String)
}

struct PlayerSnapshot: Equatable {
    static let kugouLyricLead: TimeInterval = 0.5
    static let netEaseLyricLead: TimeInterval = 0.5

    var availability: PlayerAvailability
    var track: TrackIdentity?
    var progress: TimeInterval = 0
    var isPlaying = false
    var player: PlayerKind?

    var normalizedProgress: TimeInterval {
        guard let duration = track?.duration, duration > 0 else { return max(0, progress) }
        let positive = max(0, progress)
        if positive <= duration { return positive }
        return positive.truncatingRemainder(dividingBy: duration)
    }

    var lyricProgress: TimeInterval {
        let lead: TimeInterval
        switch player {
        case .kugou: lead = Self.kugouLyricLead
        case .netease where isPlaying: lead = Self.netEaseLyricLead
        case .netease, nil: lead = 0
        }
        return normalizedProgress + lead
    }
}

enum PlayerCommand: Equatable { case previous, playPause, next }

@MainActor
enum PlayerCommandRouter {
    static func perform(
        _ command: PlayerCommand,
        mediaRemote: () -> Bool,
        accessibility: () throws -> Void
    ) throws {
        // MediaRemote's success result only acknowledges dispatch. Track
        // navigation must use the selected player's explicit menu command.
        if command == .playPause, mediaRemote() { return }
        try accessibility()
    }
}

@MainActor
protocol PlayerAdapter: AnyObject {
    var kind: PlayerKind? { get }
    var isRunning: Bool { get }
    func snapshot() -> PlayerSnapshot
    func perform(_ command: PlayerCommand) throws
    func requestPermission()
}

@MainActor
final class NetEasePlayerAdapter: PlayerAdapter {
    static let bundleIdentifier = PlayerBundleIdentifiers.netease

    private let bridge: MediaRemoteBridge
    private let audioActivity: AudioPlaybackActivityProviding
    private let applications: PlayerApplicationRegistry
    private let localPlayback = NetEaseLocalPlaybackBridge()
    private let accessibility = NetEaseAccessibilityCommandBridge()
    private var retention = PlayerSnapshotRetention()

    init(
        bridge: MediaRemoteBridge,
        audioActivity: AudioPlaybackActivityProviding? = nil,
        applications: PlayerApplicationRegistry? = nil
    ) {
        self.bridge = bridge
        self.audioActivity = audioActivity ?? CoreAudioPlaybackActivity()
        self.applications = applications ?? PlayerApplicationRegistry()
    }

    let kind: PlayerKind? = .netease
    var isRunning: Bool { !applications.processIdentifiers(for: Self.bundleIdentifier).isEmpty }

    func requestPermission() { accessibility.requestPermission() }

    func snapshot() -> PlayerSnapshot {
        guard let application = applications.runningApplications(for: Self.bundleIdentifier).first else {
            localPlayback.reset()
            retention.reset()
            return .init(availability: .notRunning, player: .netease)
        }

        let processIdentifiers = applications.processIdentifiers(for: Self.bundleIdentifier)
        let audible = audioActivity.isRunningOutput(
            bundleIdentifier: Self.bundleIdentifier,
            processIdentifiers: processIdentifiers
        )
        let localSnapshot = localPlayback.snapshot(
            processIdentifier: application.processIdentifier,
            audible: audible
        )
        // NetEase 3.1.8's local lastPlaying value is the exact state used by
        // its own UI. Prefer it once available; MediaRemote can retain an older
        // whole-second sample and briefly pull lyrics back across a boundary.
        if localSnapshot.track != nil {
            return retention.resolve(candidate: localSnapshot, audible: audible)
        }
        bridge.update()
        if let state = bridge.state, state.bundleIdentifier == Self.bundleIdentifier {
            let snapshot = state.snapshot(player: .netease, audible: audible)
            return retention.resolve(candidate: snapshot, audible: snapshot.isPlaying ? true : audible)
        }
        return retention.resolve(candidate: localSnapshot, audible: audible)
    }

    func perform(_ command: PlayerCommand) throws {
        guard let processIdentifier = applications.processIdentifiers(for: Self.bundleIdentifier).first else {
            throw AXPlayerError.notRunning
        }
        try PlayerCommandRouter.perform(command, mediaRemote: {
            bridge.perform(command, expectedBundleIdentifier: Self.bundleIdentifier)
        }, accessibility: {
            guard accessibility.isTrusted else {
                accessibility.requestPermission()
                throw AXPlayerError.permissionRequired
            }
            guard accessibility.perform(command, processIdentifier: processIdentifier) else {
                throw AXPlayerError.controlUnavailable
            }
        })
    }
}

enum AXPlayerError: LocalizedError {
    case permissionRequired, notRunning, controlUnavailable
    var errorDescription: String? {
        switch self {
        case .permissionRequired: "需要辅助功能权限"
        case .notRunning: "当前播放器尚未运行"
        case .controlUnavailable: "当前播放器暂时无法执行此控制"
        }
    }
}

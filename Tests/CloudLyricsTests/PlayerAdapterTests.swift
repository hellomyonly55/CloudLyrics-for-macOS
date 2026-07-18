import XCTest
@testable import CloudLyrics

@MainActor
final class PlayerAdapterTests: XCTestCase {
    func testPlayerProcessStateTracksLaunchesAndTerminations() {
        var state = PlayerProcessState()
        state.applicationLaunched(bundleIdentifier: PlayerBundleIdentifiers.kugou, processIdentifier: 42)
        state.applicationLaunched(bundleIdentifier: PlayerBundleIdentifiers.kugou, processIdentifier: 7)
        state.applicationLaunched(bundleIdentifier: PlayerBundleIdentifiers.kugou, processIdentifier: 42)
        XCTAssertEqual(state.identifiers(for: PlayerBundleIdentifiers.kugou), [7, 42])

        state.applicationTerminated(bundleIdentifier: PlayerBundleIdentifiers.kugou, processIdentifier: 7)
        XCTAssertEqual(state.identifiers(for: PlayerBundleIdentifiers.kugou), [42])
        XCTAssertTrue(state.identifiers(for: PlayerBundleIdentifiers.netease).isEmpty)
    }

    func testAutomaticAdapterRoutesCommandsToSelectedPlayer() throws {
        let netease = MockPlayerAdapter(kind: .netease, running: false)
        let kugou = MockPlayerAdapter(kind: .kugou, running: true)
        let adapter = AutomaticPlayerAdapter(netease: netease, kugou: kugou)

        XCTAssertEqual(adapter.snapshot().player, .kugou)
        try adapter.perform(.next)
        XCTAssertEqual(kugou.commands, [.next])
        XCTAssertTrue(netease.commands.isEmpty)
    }

    func testAutomaticAdapterFollowsBackgroundAudioOutput() {
        let netease = MockPlayerAdapter(kind: .netease, running: true)
        let kugou = MockPlayerAdapter(kind: .kugou, running: true)
        let activity = MockAudioPlaybackActivity(values: [
            PlayerBundleIdentifiers.netease: true,
            PlayerBundleIdentifiers.kugou: false
        ])
        let adapter = AutomaticPlayerAdapter(netease: netease, kugou: kugou, audioActivity: activity)

        XCTAssertEqual(adapter.snapshot().player, .netease)
    }

    func testKugouRetainsLastSnapshotWhileOverlayHidesPlaybackBar() {
        var retention = KugouSnapshotRetention()
        let start = Date(timeIntervalSince1970: 4_000)
        let track = TrackIdentity(title: "Song", artist: "Artist", duration: 200, player: .kugou)
        let valid = PlayerSnapshot(
            availability: .ready,
            track: track,
            progress: 50,
            isPlaying: true,
            player: .kugou
        )
        XCTAssertEqual(retention.resolve(candidate: valid, audible: true, now: start), valid)

        let missing = PlayerSnapshot(availability: .connecting("正在等待酷狗播放信息…"), player: .kugou)
        let retained = retention.resolve(candidate: missing, audible: true, now: start.addingTimeInterval(3))
        XCTAssertEqual(retained.availability, .ready)
        XCTAssertEqual(retained.track, track)
        XCTAssertEqual(retained.progress, 53, accuracy: 0.001)
        XCTAssertTrue(retained.isPlaying)
    }

    func testKugouRetentionFreezesWhenAudioStopsAndDoesNotMaskPermissionErrors() {
        var retention = KugouSnapshotRetention()
        let start = Date(timeIntervalSince1970: 5_000)
        let valid = PlayerSnapshot(
            availability: .ready,
            track: .init(title: "Song", artist: "Artist", player: .kugou),
            progress: 25,
            isPlaying: true,
            player: .kugou
        )
        _ = retention.resolve(candidate: valid, audible: true, now: start)

        let missing = PlayerSnapshot(availability: .connecting("missing"), player: .kugou)
        let paused = retention.resolve(candidate: missing, audible: false, now: start.addingTimeInterval(5))
        XCTAssertEqual(paused.progress, 25, accuracy: 0.001)
        XCTAssertFalse(paused.isPlaying)

        let permission = PlayerSnapshot(availability: .permissionRequired, player: .kugou)
        XCTAssertEqual(retention.resolve(candidate: permission, audible: true, now: start.addingTimeInterval(6)), permission)
    }
}

private struct MockAudioPlaybackActivity: AudioPlaybackActivityProviding {
    var values: [String: Bool]
    func isRunningOutput(bundleIdentifier: String) -> Bool? { values[bundleIdentifier] }
}

@MainActor
private final class MockPlayerAdapter: PlayerAdapter {
    let kind: PlayerKind?
    var isRunning: Bool
    var commands: [PlayerCommand] = []

    init(kind: PlayerKind, running: Bool) {
        self.kind = kind
        isRunning = running
    }

    func snapshot() -> PlayerSnapshot {
        .init(
            availability: isRunning ? .ready : .notRunning,
            track: isRunning ? .init(title: "Song", artist: "Artist", player: kind ?? .netease) : nil,
            player: kind
        )
    }

    func perform(_ command: PlayerCommand) throws { commands.append(command) }
    func requestPermission() {}
}

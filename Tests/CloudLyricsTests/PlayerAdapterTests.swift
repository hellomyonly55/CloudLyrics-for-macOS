import XCTest
@testable import CloudLyrics

@MainActor
final class PlayerAdapterTests: XCTestCase {
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

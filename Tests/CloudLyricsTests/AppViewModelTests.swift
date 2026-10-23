import Combine
import XCTest
@testable import CloudLyrics

@MainActor
final class AppViewModelTests: XCTestCase {
    func testCalibrationUsesInjectedSettingsAndPreservesPausePosition() async throws {
        let name = "CloudLyricsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = SettingsStore(defaults: defaults)
        settings.synchronization.neteaseLead = 0
        settings.appearance.mode = .single
        let player = TestPlayer(progress: 4.9)
        let model = AppViewModel(player: player, providers: [TestLyricsProvider()], settings: settings, automaticallyRefresh: false)
        try await waitForLyrics(model)
        XCTAssertEqual(model.currentLines.0, "first")
        XCTAssertNil(model.currentLines.1)
        settings.synchronization.neteaseLead = 0.2
        XCTAssertEqual(model.currentLines.0, "second")
        settings.synchronization.neteaseLead = -5
        XCTAssertEqual(model.currentLines.0, "前奏…")
        XCTAssertEqual(model.snapshot.progress, 4.9)
    }

    func testBoundaryChangesLyricsWithoutPollingPlayer() async throws {
        let name = "CloudLyricsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = SettingsStore(defaults: defaults)
        settings.synchronization.neteaseLead = 0
        settings.synchronization.refreshMode = .energySaving
        let player = TestPlayer(progress: 4.75, playing: true)
        let model = AppViewModel(player: player, providers: [TestLyricsProvider()], settings: settings)
        try await waitForLyrics(model)
        XCTAssertEqual(model.currentLines.0, "first")
        let changed = expectation(description: "Lyric boundary fires between player samples")
        var fulfilled = false
        let subscription = model.objectWillChange.sink {
            if !fulfilled, model.currentLines.0 == "second" {
                fulfilled = true
                changed.fulfill()
            }
        }
        await fulfillment(of: [changed], timeout: 0.8)
        withExtendedLifetime(subscription) {}
        XCTAssertEqual(player.sampleCount, 1)
    }

    func testControlFailureIsVisibleEvenWithLoadedLyrics() async throws {
        let player = TestPlayer(progress: 0)
        player.commandError = AXPlayerError.controlUnavailable
        let model = AppViewModel(player: player, providers: [TestLyricsProvider()], automaticallyRefresh: false)
        try await waitForLyrics(model)
        model.perform(.next)
        XCTAssertEqual(model.currentLines.0, AXPlayerError.controlUnavailable.localizedDescription)
        XCTAssertNotNil(model.document)
    }

    private func waitForLyrics(_ model: AppViewModel) async throws {
        for _ in 0..<100 {
            if model.document != nil { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Lyrics did not load")
    }
}

@MainActor
private final class TestPlayer: PlayerAdapter {
    let kind: PlayerKind? = .netease
    let isRunning = true
    var sampleCount = 0
    var commandError: Error?
    let state: PlayerSnapshot
    init(progress: TimeInterval, playing: Bool = false) {
        state = .init(availability: .ready,
                      track: .init(title: "Test", artist: "Test", duration: 30, sourceID: UUID().uuidString),
                      progress: progress, isPlaying: playing, player: .netease)
    }
    func snapshot() -> PlayerSnapshot { sampleCount += 1; return state }
    func perform(_ command: PlayerCommand) throws {
        if let commandError { throw commandError }
    }
    func requestPermission() {}
}

private struct TestLyricsProvider: LyricsProvider {
    let name = "Test"
    func lyrics(for track: TrackIdentity) async throws -> LyricsDocument {
        .init(track: track, lines: [.init(time: 0, text: "first", translation: "translation"),
                                    .init(time: 5, text: "second")], source: name)
    }
}

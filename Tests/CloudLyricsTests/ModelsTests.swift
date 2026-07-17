import XCTest
@testable import CloudLyrics

final class ModelsTests: XCTestCase {
    func testPlayerNamespacedKeysAndLegacyDecode() throws {
        let netease = TrackIdentity(title: "Same", artist: "Singer", sourceID: "123", player: .netease)
        let kugou = TrackIdentity(title: "Same", artist: "Singer", sourceID: "123", player: .kugou)
        XCTAssertEqual(netease.normalizedKey, "netease:123")
        XCTAssertEqual(kugou.normalizedKey, "kugou:123")
        let legacy = try JSONDecoder().decode(TrackIdentity.self, from: Data(#"{"title":"Old","artist":"Artist","sourceID":"9"}"#.utf8))
        XCTAssertEqual(legacy.player, .netease)
        XCTAssertEqual(legacy.normalizedKey, "netease:9")
    }

    func testAutomaticPlayerSelectionFollowsActiveAndKeepsPrevious() {
        XCTAssertEqual(AutomaticPlayerSelection.choose(activeBundleIdentifier: PlayerBundleIdentifiers.kugou, previous: .netease, neteaseRunning: true, kugouRunning: true), .kugou)
        XCTAssertEqual(AutomaticPlayerSelection.choose(activeBundleIdentifier: PlayerBundleIdentifiers.netease, previous: .kugou, neteaseRunning: true, kugouRunning: true), .netease)
        XCTAssertEqual(AutomaticPlayerSelection.choose(activeBundleIdentifier: nil, previous: .kugou, neteaseRunning: true, kugouRunning: true), .kugou)
        XCTAssertEqual(AutomaticPlayerSelection.choose(activeBundleIdentifier: nil, previous: .netease, neteaseRunning: true, kugouRunning: true, kugouPlaying: true), .kugou)
        XCTAssertEqual(AutomaticPlayerSelection.choose(activeBundleIdentifier: nil, previous: nil, neteaseRunning: false, kugouRunning: true), .kugou)
        XCTAssertNil(AutomaticPlayerSelection.choose(activeBundleIdentifier: nil, previous: .kugou, neteaseRunning: false, kugouRunning: false))
    }

    func testFrontmostPlayerIsUsedOnlyAsFallback() {
        XCTAssertEqual(
            AutomaticPlayerSelection.choose(
                activeBundleIdentifier: nil,
                frontmostBundleIdentifier: PlayerBundleIdentifiers.netease,
                previous: .kugou,
                neteaseRunning: true,
                kugouRunning: true
            ),
            .netease
        )
        XCTAssertEqual(
            AutomaticPlayerSelection.choose(
                activeBundleIdentifier: nil,
                previous: .kugou,
                neteaseRunning: true,
                kugouRunning: true,
                neteasePlaying: true
            ),
            .netease
        )
    }

    func testBackgroundAudioOverridesFrontmostPlayer() {
        XCTAssertEqual(
            AutomaticPlayerSelection.choose(
                activeBundleIdentifier: nil,
                frontmostBundleIdentifier: PlayerBundleIdentifiers.kugou,
                previous: .kugou,
                neteaseRunning: true,
                kugouRunning: true,
                neteaseAudible: true,
                kugouAudible: false
            ),
            .netease
        )
        XCTAssertEqual(
            AutomaticPlayerSelection.choose(
                activeBundleIdentifier: nil,
                frontmostBundleIdentifier: PlayerBundleIdentifiers.netease,
                previous: .netease,
                neteaseRunning: true,
                kugouRunning: true,
                neteaseAudible: false,
                kugouAudible: true
            ),
            .kugou
        )
    }

    func testTrackNormalizationRemovesVersionAndWhitespace() {
        XCTAssertEqual(TrackIdentity.normalize("晴天（Live 版） "), "晴天")
        XCTAssertEqual(TrackIdentity.normalize("Hello [Remastered]"), "hello")
    }

    func testLineIndexAtBoundariesAndEnd() {
        let track = TrackIdentity(title: "t", artist: "a")
        let document = LyricsDocument(track: track, lines: [
            .init(time: 1, text: "one"), .init(time: 3, text: "three"), .init(time: 5, text: "five")
        ], source: "test")
        XCTAssertEqual(document.lineIndex(at: 0), 0)
        XCTAssertEqual(document.lineIndex(at: 3), 1)
        XCTAssertEqual(document.lineIndex(at: 100), 2)
    }

    func testOffsetAffectsLookup() {
        let track = TrackIdentity(title: "t", artist: "a")
        let document = LyricsDocument(track: track, lines: [.init(time: 1, text: "one"), .init(time: 2, text: "two")], source: "test", offset: 0.5)
        XCTAssertEqual(document.lineIndex(at: 2.4), 0)
        XCTAssertEqual(document.lineIndex(at: 2.5), 1)
    }

    func testPlayerProgressWrapsWithinDuration() {
        let track = TrackIdentity(title: "t", artist: "a", duration: 203)
        let snapshot = PlayerSnapshot(availability: .ready, track: track, progress: 973, isPlaying: true)
        XCTAssertEqual(snapshot.normalizedProgress, 161, accuracy: 0.001)
    }

    func testKugouLyricsUseHalfSecondLeadWithoutAffectingNetEase() {
        let track = TrackIdentity(title: "t", artist: "a", duration: 203, player: .kugou)
        let kugou = PlayerSnapshot(availability: .ready, track: track, progress: 10, isPlaying: true, player: .kugou)
        let netease = PlayerSnapshot(
            availability: .ready,
            track: .init(title: "t", artist: "a", duration: 203, player: .netease),
            progress: 10,
            isPlaying: true,
            player: .netease
        )
        XCTAssertEqual(kugou.lyricProgress, 10.5, accuracy: 0.001)
        XCTAssertEqual(netease.lyricProgress, 10, accuracy: 0.001)
    }

    func testSystemProgressAdvancesWithoutMediaTimestamp() {
        let state = SystemNowPlayingState(
            processIdentifier: 1,
            title: "Song",
            artist: "Artist",
            elapsed: 10,
            rate: 1,
            timestamp: nil,
            observedAt: Date().addingTimeInterval(-2)
        )
        XCTAssertEqual(state.currentProgress, 12, accuracy: 0.1)
    }

    func testTranslationModeUsesTranslationWhenAvailable() {
        let document = lyrics([.init(time: 0, text: "原文", translation: "Translation"), .init(time: 5, text: "下一句")])
        XCTAssertEqual(LyricPresentation.make(document: document, index: 0, mode: .translation), .init(primary: "原文", secondary: "Translation"))
    }

    func testTranslationModeFallsBackToNextLine() {
        let document = lyrics([.init(time: 0, text: "当前句"), .init(time: 5, text: "下一句")])
        XCTAssertEqual(LyricPresentation.make(document: document, index: 0, mode: .translation), .init(primary: "当前句", secondary: "下一句"))
        XCTAssertEqual(LyricPresentation.make(document: document, index: 1, mode: .translation), .init(primary: "下一句", secondary: nil))
    }

    func testSingleAndNextLineModes() {
        let document = lyrics([.init(time: 0, text: "当前句", translation: "翻译"), .init(time: 5, text: "下一句")])
        XCTAssertEqual(LyricPresentation.make(document: document, index: 0, mode: .single), .init(primary: "当前句", secondary: nil))
        XCTAssertEqual(LyricPresentation.make(document: document, index: 0, mode: .nextLine), .init(primary: "当前句", secondary: "下一句"))
    }

    func testNetEaseCommandsTargetOnlyNetEaseDOM() {
        XCTAssertEqual(NetEaseCEFCommand.selector(for: .previous), "[data-log*='btn_pc_previous']")
        XCTAssertEqual(NetEaseCEFCommand.selector(for: .playPause), "#btn_pc_minibar_play")
        XCTAssertEqual(NetEaseCEFCommand.selector(for: .next), "[data-log*='btn_pc_next']")
        XCTAssertTrue(NetEaseCEFCommand.expression(for: .next).contains("document.querySelector"))
    }

    func testNetEaseCEFEndpointAcceptsOnlyExpectedLocalWebSocket() {
        XCTAssertNotNil(NetEaseCEFEndpoint.validatedWebSocketURL(from: "ws://127.0.0.1:9222/devtools/page/123"))
        XCTAssertNil(NetEaseCEFEndpoint.validatedWebSocketURL(from: "ws://localhost:9222/devtools/page/123"))
        XCTAssertNil(NetEaseCEFEndpoint.validatedWebSocketURL(from: "ws://192.168.1.2:9222/devtools/page/123"))
        XCTAssertNil(NetEaseCEFEndpoint.validatedWebSocketURL(from: "ws://127.0.0.1:9333/devtools/page/123"))
        XCTAssertNil(NetEaseCEFEndpoint.validatedWebSocketURL(from: "wss://127.0.0.1:9222/devtools/page/123"))
        XCTAssertNil(NetEaseCEFEndpoint.validatedWebSocketURL(from: "not a url"))
    }

    private func lyrics(_ lines: [TimedLyricLine]) -> LyricsDocument {
        .init(track: .init(title: "t", artist: "a"), lines: lines, source: "test")
    }
}

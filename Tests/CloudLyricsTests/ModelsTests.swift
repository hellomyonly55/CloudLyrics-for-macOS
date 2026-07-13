import XCTest
@testable import CloudLyrics

final class ModelsTests: XCTestCase {
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

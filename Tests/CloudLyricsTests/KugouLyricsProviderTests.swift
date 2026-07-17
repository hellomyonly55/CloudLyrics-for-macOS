import XCTest
@testable import CloudLyrics

final class KugouLyricsProviderTests: XCTestCase {
    func testSelectsMatchingLocalLRC() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data("[00:01.00]wrong".utf8).write(to: folder.appendingPathComponent("Other - Song_deadbeefdeadbeefdeadbeefdeadbeef.lrc"))
        try Data("[00:02.00]matched".utf8).write(to: folder.appendingPathComponent("Singer - Song (Live)_0123456789abcdef0123456789abcdef.lrc"))

        let track = TrackIdentity(title: "Song", artist: "Singer", duration: 10, player: .kugou)
        let document = try await KugouLocalLyricsProvider(directory: folder).lyrics(for: track)
        XCTAssertEqual(document.lines, [.init(time: 2, text: "matched")])
        XCTAssertEqual(document.source, "酷狗音乐（本地）")
        XCTAssertEqual(document.track.player, .kugou)
    }

    func testRejectsOtherPlayersAndMissingMatches() async {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let provider = KugouLocalLyricsProvider(directory: folder)
        do {
            _ = try await provider.lyrics(for: .init(title: "Song", artist: "Singer", player: .netease))
            XCTFail("Expected noMatch")
        } catch { XCTAssertEqual(error as? LyricsError, .noMatch) }
    }

    func testPrefersKRCWhenCandidatesHaveSameMatch() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data("[00:01.00]lrc".utf8).write(to: folder.appendingPathComponent("Singer - Song_0123456789abcdef0123456789abcdef.lrc"))
        try makeKRCFixture("[2000,500]<0,500,0>krc").write(to: folder.appendingPathComponent("Singer - Song_abcdef0123456789abcdef0123456789.krc"))

        let track = TrackIdentity(title: "Song", artist: "Singer", player: .kugou)
        let document = try await KugouLocalLyricsProvider(directory: folder).lyrics(for: track)
        XCTAssertEqual(document.lines, [.init(time: 2, text: "krc")])
    }
}

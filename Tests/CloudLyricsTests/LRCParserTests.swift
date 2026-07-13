import XCTest
@testable import CloudLyrics

final class LRCParserTests: XCTestCase {
    func testParsesMultipleTimestampsAndTranslation() {
        let original = "[00:01.00][00:03.50]你好\n[00:05.250]世界"
        let translated = "[00:01.00]Hello\n[00:05.25]World"
        let result = LRCParser.parse(original, translation: translated)
        XCTAssertEqual(result.lines.count, 3)
        XCTAssertEqual(result.lines[0], .init(time: 1, text: "你好", translation: "Hello"))
        XCTAssertEqual(result.lines[1].time, 3.5, accuracy: 0.001)
        XCTAssertNil(result.lines[1].translation)
        XCTAssertEqual(result.lines[2].translation, "World")
    }

    func testOffsetAndEmptyLines() {
        let result = LRCParser.parse("[offset:+500]\n[00:01.00] \n[00:02.00]line")
        XCTAssertEqual(result.offset, 0.5)
        XCTAssertEqual(result.lines, [.init(time: 2, text: "line")])
    }

    func testStableDuplicateTimestamps() {
        let result = LRCParser.parse("[00:01]first\n[00:01]second")
        XCTAssertEqual(result.lines.map(\.text), ["first", "second"])
    }
}

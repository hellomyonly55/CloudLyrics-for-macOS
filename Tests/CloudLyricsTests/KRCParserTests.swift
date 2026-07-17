import Compression
import XCTest
@testable import CloudLyrics

final class KRCParserTests: XCTestCase {
    func testDecryptsWordsOffsetAndTranslation() throws {
        let language = #"{"content":[{"lyricContent":[["roman"],["second"]],"type":0},{"lyricContent":[["翻译一"],[""]],"type":1}]}"#
        let encodedLanguage = Data(language.utf8).base64EncodedString()
        let text = """
        [offset:+250]
        [language:\(encodedLanguage)]
        [1000,900]<0,300,0>Hello <300,600,0>world
        [2000,500]<0,500,0>Next
        """
        let result = try KRCParser.parse(makeKRCFixture(text))
        XCTAssertEqual(result.offset, 0.25, accuracy: 0.001)
        XCTAssertEqual(result.lines, [
            .init(time: 1, text: "Hello world", translation: "翻译一"),
            .init(time: 2, text: "Next")
        ])
    }

    func testDecodedParserSkipsEmptyAndKeepsDuplicateTimesStable() {
        let result = KRCParser.parseDecoded("[1000,10]<0,10,0>first\n[1000,10]<0,10,0>second\n[2000,10]<0,10,0>   ")
        XCTAssertEqual(result.lines.map(\.text), ["first", "second"])
    }

    func testRejectsInvalidHeaderAndCompressedData() {
        XCTAssertThrowsError(try KRCParser.parse(Data("nope".utf8))) { XCTAssertEqual($0 as? KRCParserError, .invalidHeader) }
        XCTAssertThrowsError(try KRCParser.parse(Data("krc1broken".utf8))) { XCTAssertEqual($0 as? KRCParserError, .invalidCompressedData) }
    }

}

func makeKRCFixture(_ text: String) -> Data {
    let source = Data(text.utf8)
    var compressed = Data(count: max(1024, source.count * 2))
    let count = compressed.withUnsafeMutableBytes { destination in
        source.withUnsafeBytes { input in
            compression_encode_buffer(
                destination.bindMemory(to: UInt8.self).baseAddress!, destination.count,
                input.bindMemory(to: UInt8.self).baseAddress!, input.count,
                nil, COMPRESSION_ZLIB
            )
        }
    }
    compressed.count = count
    let key: [UInt8] = [64, 71, 97, 119, 94, 50, 116, 71, 81, 54, 49, 45, 206, 210, 110, 105]
    let encrypted = Data(compressed.enumerated().map { index, byte in byte ^ key[index % key.count] })
    return Data("krc1".utf8) + encrypted
}

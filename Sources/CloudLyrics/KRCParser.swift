import Compression
import Darwin
import Foundation

enum KRCParserError: Error, Equatable {
    case invalidHeader
    case invalidCompressedData
    case invalidText
}

enum KRCParser {
    private static let header = Data("krc1".utf8)
    private static let key: [UInt8] = [64, 71, 97, 119, 94, 50, 116, 71, 81, 54, 49, 45, 206, 210, 110, 105]
    private static let lineRegex = try! NSRegularExpression(pattern: #"^\[(\d+),(\d+)\](.*)$"#)
    private static let wordRegex = try! NSRegularExpression(pattern: #"<\d+,\d+,\d+>"#)
    private static let offsetRegex = try! NSRegularExpression(pattern: #"^\[offset:([+-]?\d+)\]$"#, options: .caseInsensitive)

    static func parse(_ data: Data) throws -> (lines: [TimedLyricLine], offset: TimeInterval) {
        guard data.count > header.count, data.prefix(header.count) == header else { throw KRCParserError.invalidHeader }
        let encrypted = data.dropFirst(header.count)
        let compressed = Data(encrypted.enumerated().map { index, byte in byte ^ key[index % key.count] })
        guard let inflated = decompress(compressed) ?? decompressWithLibz(compressed) else { throw KRCParserError.invalidCompressedData }
        guard let text = String(data: inflated, encoding: .utf8) else { throw KRCParserError.invalidText }
        return parseDecoded(text)
    }

    static func parseDecoded(_ text: String) -> (lines: [TimedLyricLine], offset: TimeInterval) {
        var lines: [TimedLyricLine] = []
        var offset: TimeInterval = 0
        var translations: [String] = []

        for rawLine in text.components(separatedBy: .newlines) {
            let range = NSRange(rawLine.startIndex..., in: rawLine)
            if let match = offsetRegex.firstMatch(in: rawLine, range: range),
               let valueRange = Range(match.range(at: 1), in: rawLine),
               let milliseconds = Double(rawLine[valueRange]) {
                offset = milliseconds / 1000
                continue
            }
            if rawLine.hasPrefix("[language:"), rawLine.hasSuffix("]") {
                let start = rawLine.index(rawLine.startIndex, offsetBy: 10)
                translations = translationLines(from: String(rawLine[start..<rawLine.index(before: rawLine.endIndex)]))
                continue
            }
            guard let match = lineRegex.firstMatch(in: rawLine, range: range),
                  let timeRange = Range(match.range(at: 1), in: rawLine),
                  let contentRange = Range(match.range(at: 3), in: rawLine),
                  let milliseconds = Double(rawLine[timeRange]) else { continue }
            let content = String(rawLine[contentRange])
            let contentNSRange = NSRange(content.startIndex..., in: content)
            let lyric = wordRegex.stringByReplacingMatches(in: content, range: contentNSRange, withTemplate: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !lyric.isEmpty else { continue }
            lines.append(.init(time: milliseconds / 1000, text: lyric))
        }

        lines = lines.enumerated().map { index, line in
            var value = line
            if translations.indices.contains(index) {
                let translation = translations[index].trimmingCharacters(in: .whitespacesAndNewlines)
                value.translation = translation.isEmpty ? nil : translation
            }
            return value
        }
        lines.sort { $0.time < $1.time }
        return (lines, offset)
    }

    private static func translationLines(from base64: String) -> [String] {
        guard let data = Data(base64Encoded: base64),
              let root = try? JSONDecoder().decode(LanguageRoot.self, from: data),
              let translation = root.content.first(where: { $0.type == 1 }) else { return [] }
        return translation.lyricContent.map { $0.joined() }
    }

    private static func decompress(_ data: Data) -> Data? {
        let dummyDestination = UnsafeMutablePointer<UInt8>.allocate(capacity: 1)
        let dummySource = UnsafePointer(dummyDestination)
        defer { dummyDestination.deallocate() }
        var stream = compression_stream(dst_ptr: dummyDestination, dst_size: 0, src_ptr: dummySource, src_size: 0, state: nil)
        guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) != COMPRESSION_STATUS_ERROR else { return nil }
        defer { compression_stream_destroy(&stream) }

        return data.withUnsafeBytes { sourceBuffer -> Data? in
            guard let source = sourceBuffer.bindMemory(to: UInt8.self).baseAddress else { return nil }
            stream.src_ptr = source
            stream.src_size = data.count
            let capacity = 64 * 1024
            let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
            defer { destination.deallocate() }
            var output = Data()

            while true {
                stream.dst_ptr = destination
                stream.dst_size = capacity
                let status = compression_stream_process(&stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                let produced = capacity - stream.dst_size
                if produced > 0 { output.append(destination, count: produced) }
                if status == COMPRESSION_STATUS_END { return output }
                if status == COMPRESSION_STATUS_ERROR { return nil }
                if produced == 0 && stream.src_size == 0 { return nil }
            }
        }
    }

    private static func decompressWithLibz(_ data: Data) -> Data? {
        typealias Uncompress = @convention(c) (
            UnsafeMutablePointer<UInt8>, UnsafeMutablePointer<UInt>, UnsafePointer<UInt8>, UInt
        ) -> Int32
        guard !data.isEmpty,
              let handle = dlopen("/usr/lib/libz.1.dylib", RTLD_LAZY | RTLD_LOCAL),
              let symbol = dlsym(handle, "uncompress") else { return nil }
        defer { dlclose(handle) }
        let uncompress = unsafeBitCast(symbol, to: Uncompress.self)
        var capacity = max(64 * 1024, data.count * 8)

        while capacity <= 16 * 1024 * 1024 {
            var output = Data(count: capacity)
            var outputLength = UInt(capacity)
            let status = output.withUnsafeMutableBytes { destination in
                data.withUnsafeBytes { source in
                    uncompress(
                        destination.bindMemory(to: UInt8.self).baseAddress!, &outputLength,
                        source.bindMemory(to: UInt8.self).baseAddress!, UInt(data.count)
                    )
                }
            }
            if status == 0 {
                output.count = Int(outputLength)
                return output
            }
            guard status == -5 else { return nil } // Z_BUF_ERROR
            capacity *= 2
        }
        return nil
    }
}

private struct LanguageRoot: Decodable {
    let content: [LanguageContent]
}

private struct LanguageContent: Decodable {
    let lyricContent: [[String]]
    let type: Int
}

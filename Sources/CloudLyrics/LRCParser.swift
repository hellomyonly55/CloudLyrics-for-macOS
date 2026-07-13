import Foundation

enum LRCParser {
    private static let timeRegex = try! NSRegularExpression(pattern: #"\[(\d{1,3}):(\d{2}(?:\.\d{1,3})?)\]"#)
    private static let offsetRegex = try! NSRegularExpression(pattern: #"\[offset:([+-]?\d+)\]"#, options: .caseInsensitive)

    static func parse(_ lrc: String, translation: String? = nil) -> (lines: [TimedLyricLine], offset: TimeInterval) {
        let original = parseSingle(lrc)
        let translated = parseSingle(translation ?? "").lines
        let translationByTime = Dictionary(translated.map { (timeKey($0.time), $0.text) }, uniquingKeysWith: { first, _ in first })
        let lines = original.lines.map {
            TimedLyricLine(time: $0.time, text: $0.text, translation: translationByTime[timeKey($0.time)])
        }
        return (lines, original.offset)
    }

    private static func parseSingle(_ lrc: String) -> (lines: [TimedLyricLine], offset: TimeInterval) {
        var output: [TimedLyricLine] = []
        var offset: TimeInterval = 0
        for rawLine in lrc.components(separatedBy: .newlines) {
            let range = NSRange(rawLine.startIndex..., in: rawLine)
            if let match = offsetRegex.firstMatch(in: rawLine, range: range),
               let valueRange = Range(match.range(at: 1), in: rawLine),
               let milliseconds = Double(rawLine[valueRange]) {
                offset = milliseconds / 1000
            }
            let matches = timeRegex.matches(in: rawLine, range: range)
            guard !matches.isEmpty else { continue }
            let text = timeRegex.stringByReplacingMatches(in: rawLine, range: range, withTemplate: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            for match in matches {
                guard let minuteRange = Range(match.range(at: 1), in: rawLine),
                      let secondRange = Range(match.range(at: 2), in: rawLine),
                      let minutes = Double(rawLine[minuteRange]), let seconds = Double(rawLine[secondRange]) else { continue }
                output.append(.init(time: minutes * 60 + seconds, text: text))
            }
        }
        output.sort { $0.time < $1.time }
        return (output, offset)
    }

    private static func timeKey(_ value: TimeInterval) -> Int { Int((value * 100).rounded()) }
}

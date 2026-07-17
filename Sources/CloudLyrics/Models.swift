import Foundation
import SwiftUI

enum PlayerKind: String, Codable, CaseIterable, Sendable {
    case netease
    case kugou

    var displayName: String {
        switch self {
        case .netease: "网易云音乐"
        case .kugou: "酷狗音乐"
        }
    }
}

struct TrackIdentity: Codable, Equatable, Hashable, Sendable {
    var title: String
    var artist: String
    var duration: TimeInterval?
    var sourceID: String?
    var player: PlayerKind

    init(title: String, artist: String, duration: TimeInterval? = nil, sourceID: String? = nil, player: PlayerKind = .netease) {
        self.title = title
        self.artist = artist
        self.duration = duration
        self.sourceID = sourceID
        self.player = player
    }

    var normalizedKey: String {
        if let sourceID, !sourceID.isEmpty { return "\(player.rawValue):\(sourceID)" }
        return "\(player.rawValue):\(Self.normalize(title))|\(Self.normalize(artist))|\(Int((duration ?? 0).rounded()))"
    }

    static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: #"[\(\[（【].*?[\)\]）】]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
            .lowercased()
    }

    private enum CodingKeys: String, CodingKey { case title, artist, duration, sourceID, player }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        artist = try container.decode(String.self, forKey: .artist)
        duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration)
        sourceID = try container.decodeIfPresent(String.self, forKey: .sourceID)
        player = try container.decodeIfPresent(PlayerKind.self, forKey: .player) ?? .netease
    }
}

struct TimedLyricLine: Codable, Equatable, Sendable {
    var time: TimeInterval
    var text: String
    var translation: String?
}

struct LyricsDocument: Codable, Equatable, Sendable {
    var track: TrackIdentity
    var lines: [TimedLyricLine]
    var source: String
    var offset: TimeInterval = 0

    func lineIndex(at progress: TimeInterval) -> Int? {
        guard !lines.isEmpty else { return nil }
        let value = progress - offset
        var low = 0, high = lines.count
        while low < high {
            let mid = (low + high) / 2
            if lines[mid].time <= value { low = mid + 1 } else { high = mid }
        }
        return max(0, low - 1)
    }
}

enum TwoLineMode: String, CaseIterable, Codable, Identifiable {
    case translation
    case nextLine
    case single
    var id: String { rawValue }
    var label: String {
        switch self {
        case .translation: "原文 + 翻译"
        case .nextLine: "当前句 + 下一句"
        case .single: "单排歌词"
        }
    }
}

struct LyricPresentation: Equatable {
    var primary: String
    var secondary: String?

    static func make(document: LyricsDocument, index: Int, mode: TwoLineMode) -> LyricPresentation {
        guard document.lines.indices.contains(index) else { return .init(primary: "", secondary: nil) }
        let line = document.lines[index]
        let next = document.lines.indices.contains(index + 1) ? document.lines[index + 1].text : nil
        switch mode {
        case .translation:
            let translation = line.translation?.trimmingCharacters(in: .whitespacesAndNewlines)
            return .init(primary: line.text, secondary: translation?.isEmpty == false ? translation : next)
        case .nextLine:
            return .init(primary: line.text, secondary: next)
        case .single:
            return .init(primary: line.text, secondary: nil)
        }
    }
}

enum LyricsAlignment: String, CaseIterable, Codable, Identifiable {
    case leading, center, trailing
    var id: String { rawValue }
    var label: String { ["leading": "左对齐", "center": "居中", "trailing": "右对齐"][rawValue]! }
    var textAlignment: TextAlignment { self == .leading ? .leading : self == .trailing ? .trailing : .center }
    var frameAlignment: Alignment { self == .leading ? .leading : self == .trailing ? .trailing : .center }
}

struct AppearanceSettings: Codable, Equatable {
    var mode: TwoLineMode = .translation
    var primaryHex = "#FFFFFF"
    var secondaryHex = "#AEB6C2"
    var primarySize = 10.0
    var secondarySize = 8.0
    var lineSpacing = -1.0
    var width = 360.0
    var horizontalOffset = 0.0
    var alignment: LyricsAlignment = .center

    static let defaults = AppearanceSettings()
}

extension Color {
    init(hex: String) {
        let value = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let number = UInt64(value, radix: 16) ?? 0xFFFFFF
        self.init(
            red: Double((number >> 16) & 255) / 255,
            green: Double((number >> 8) & 255) / 255,
            blue: Double(number & 255) / 255
        )
    }
}

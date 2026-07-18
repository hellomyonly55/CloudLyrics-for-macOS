import Foundation

protocol LyricsProvider: Sendable {
    var name: String { get }
    func lyrics(for track: TrackIdentity) async throws -> LyricsDocument
}

enum LyricsError: LocalizedError {
    case noMatch, noLyrics, invalidResponse
    var errorDescription: String? {
        switch self {
        case .noMatch: "没有找到匹配歌曲"
        case .noLyrics: "没有可用歌词"
        case .invalidResponse: "歌词服务返回异常"
        }
    }
}

struct NetEaseLyricsProvider: LyricsProvider {
    let name = "网易云音乐"
    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    func lyrics(for track: TrackIdentity) async throws -> LyricsDocument {
        let songID: Int
        if track.player == .netease, let sourceID = track.sourceID, let exactID = Int(sourceID) {
            songID = exactID
        } else {
            let query = "\(track.title) \(track.artist)"
            var components = URLComponents(string: "https://music.163.com/api/search/get")!
            components.queryItems = [
                .init(name: "s", value: query), .init(name: "type", value: "1"),
                .init(name: "limit", value: "10"), .init(name: "offset", value: "0")
            ]
            let search: SearchResponse = try await request(components.url!)
            guard let match = search.result?.songs?.max(by: { score($0, track) < score($1, track) }), score(match, track) >= 0.45 else {
                throw LyricsError.noMatch
            }
            songID = match.id
        }
        var lyricURL = URLComponents(string: "https://music.163.com/api/song/lyric")!
        lyricURL.queryItems = [.init(name: "id", value: String(songID)), .init(name: "lv", value: "-1"), .init(name: "tv", value: "-1")]
        let response: LyricResponse = try await request(lyricURL.url!)
        guard let raw = response.lrc?.lyric else { throw LyricsError.noLyrics }
        let parsed = LRCParser.parse(raw, translation: response.tlyric?.lyric)
        guard !parsed.lines.isEmpty else { throw LyricsError.noLyrics }
        var matchedTrack = track
        if track.player == .netease { matchedTrack.sourceID = String(songID) }
        return .init(track: matchedTrack, lines: parsed.lines, source: name, offset: parsed.offset)
    }

    private func request<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue("https://music.163.com/", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 CloudLyrics/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw LyricsError.invalidResponse }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func score(_ song: SearchSong, _ track: TrackIdentity) -> Double {
        let title = similarity(TrackIdentity.normalize(song.name), TrackIdentity.normalize(track.title))
        let artists = song.artists?.map(\.name).joined(separator: " ") ?? ""
        let artist = similarity(TrackIdentity.normalize(artists), TrackIdentity.normalize(track.artist))
        let durationScore: Double
        if let expected = track.duration, let ms = song.duration, expected > 0 {
            durationScore = max(0, 1 - abs(Double(ms) / 1000 - expected) / 30)
        } else { durationScore = 0.5 }
        return title * 0.6 + artist * 0.3 + durationScore * 0.1
    }
}

struct KugouLyricFileCandidate: Equatable, Sendable {
    var url: URL
    var normalizedTitle: String
    var normalizedArtist: String
    var priority: Int
}

actor KugouLyricsDirectoryIndex {
    private var indexedDirectory: URL?
    private var directoryModificationDate: Date?
    private var cachedCandidates: [KugouLyricFileCandidate] = []

    func candidates(in directory: URL) throws -> [KugouLyricFileCandidate] {
        let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        let modificationDate = attributes[.modificationDate] as? Date
        if modificationDate != nil,
           indexedDirectory == directory,
           directoryModificationDate == modificationDate {
            return cachedCandidates
        }
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ).filter { ["krc", "lrc"].contains($0.pathExtension.lowercased()) }
        cachedCandidates = files.map(Self.makeCandidate)
        indexedDirectory = directory
        directoryModificationDate = modificationDate
        return cachedCandidates
    }

    private static func makeCandidate(_ file: URL) -> KugouLyricFileCandidate {
        var stem = file.deletingPathExtension().lastPathComponent
        stem = stem.replacingOccurrences(of: #"_[0-9a-fA-F]{32}$"#, with: "", options: .regularExpression)
        let parts = stem.components(separatedBy: " - ")
        let artist = parts.count > 1 ? parts[0] : stem
        let title = parts.count > 1 ? parts.dropFirst().joined(separator: " - ") : stem
        return .init(
            url: file,
            normalizedTitle: TrackIdentity.normalize(title),
            normalizedArtist: TrackIdentity.normalize(artist),
            priority: file.pathExtension.lowercased() == "krc" ? 1 : 0
        )
    }
}

struct KugouLocalLyricsProvider: LyricsProvider {
    let name = "酷狗音乐（本地）"
    private let directory: URL
    private let index: KugouLyricsDirectoryIndex

    init(directory: URL? = nil, index: KugouLyricsDirectoryIndex = KugouLyricsDirectoryIndex()) {
        self.directory = directory ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/com.kugou.mac.Music/Data/Documents/Caches/kgLyric", isDirectory: true)
        self.index = index
    }

    func lyrics(for track: TrackIdentity) async throws -> LyricsDocument {
        guard track.player == .kugou else { throw LyricsError.noMatch }
        let candidates = try await index.candidates(in: directory)
        let scored: [(candidate: KugouLyricFileCandidate, score: Double)] = candidates.map { candidate in
            (candidate: candidate, score: score(candidate, track))
        }
        let matches = scored.filter { $0.score >= 0.55 }
        let best = matches.max { lhs, rhs in
            if lhs.score == rhs.score { return lhs.candidate.priority < rhs.candidate.priority }
            return lhs.score < rhs.score
        }
        guard let candidate = best?.candidate.url else { throw LyricsError.noMatch }

        let data = try Data(contentsOf: candidate)
        let parsed: (lines: [TimedLyricLine], offset: TimeInterval)
        if candidate.pathExtension.lowercased() == "krc" {
            parsed = try KRCParser.parse(data)
        } else {
            guard let text = decodeLRC(data) else { throw LyricsError.invalidResponse }
            parsed = LRCParser.parse(text)
        }
        guard !parsed.lines.isEmpty else { throw LyricsError.noLyrics }
        return .init(track: track, lines: parsed.lines, source: name, offset: parsed.offset)
    }

    private func score(_ candidate: KugouLyricFileCandidate, _ track: TrackIdentity) -> Double {
        let title = similarity(candidate.normalizedTitle, TrackIdentity.normalize(track.title))
        let artist = similarity(candidate.normalizedArtist, TrackIdentity.normalize(track.artist))
        return title * 0.7 + artist * 0.3
    }

    private func decodeLRC(_ data: Data) -> String? {
        if let value = String(data: data, encoding: .utf8) { return value }
        let encoding = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        return NSString(data: data, encoding: encoding) as String?
    }
}

struct LRCLIBLyricsProvider: LyricsProvider {
    let name = "LRCLIB"
    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    func lyrics(for track: TrackIdentity) async throws -> LyricsDocument {
        var url = URLComponents(string: "https://lrclib.net/api/search")!
        url.queryItems = [.init(name: "track_name", value: track.title), .init(name: "artist_name", value: track.artist)]
        var request = URLRequest(url: url.url!, timeoutInterval: 8)
        request.setValue("CloudLyrics/1.0 (local macOS app)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw LyricsError.invalidResponse }
        let candidates = try JSONDecoder().decode([LRCLIBResult].self, from: data)
        guard let result = candidates.max(by: { lrclibScore($0, track) < lrclibScore($1, track) }),
              let raw = result.syncedLyrics else { throw LyricsError.noMatch }
        let parsed = LRCParser.parse(raw)
        guard !parsed.lines.isEmpty else { throw LyricsError.noLyrics }
        return .init(track: track, lines: parsed.lines, source: name, offset: parsed.offset)
    }
}

func similarity(_ lhs: String, _ rhs: String) -> Double {
    guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
    if lhs == rhs { return 1 }
    if lhs.contains(rhs) || rhs.contains(lhs) { return 0.82 }
    let a = Set(lhs), b = Set(rhs)
    return Double(a.intersection(b).count) / Double(max(a.union(b).count, 1))
}

private func lrclibScore(_ item: LRCLIBResult, _ track: TrackIdentity) -> Double {
    let title = similarity(TrackIdentity.normalize(item.trackName), TrackIdentity.normalize(track.title))
    let artist = similarity(TrackIdentity.normalize(item.artistName), TrackIdentity.normalize(track.artist))
    let duration: Double
    if let expected = track.duration, let actual = item.duration { duration = max(0, 1 - abs(actual - expected) / 30) } else { duration = 0.5 }
    return title * 0.6 + artist * 0.3 + duration * 0.1
}

private struct SearchResponse: Decodable { let result: SearchResult? }
private struct SearchResult: Decodable { let songs: [SearchSong]? }
private struct SearchSong: Decodable { let id: Int; let name: String; let artists: [SearchArtist]?; let duration: Int? }
private struct SearchArtist: Decodable { let name: String }
private struct LyricResponse: Decodable { let lrc: LyricValue?; let tlyric: LyricValue? }
private struct LyricValue: Decodable { let lyric: String? }
private struct LRCLIBResult: Decodable { let trackName: String; let artistName: String; let duration: Double?; let syncedLyrics: String? }

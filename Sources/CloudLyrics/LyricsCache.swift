import Foundation

actor LyricsCache {
    private struct Entry: Codable { var document: LyricsDocument; var accessedAt: Date }
    private var entries: [String: Entry] = [:]
    private let url: URL
    private let limit = 100

    init() {
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("CloudLyrics", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        url = folder.appendingPathComponent("lyrics.json")
        if let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode([String: Entry].self, from: data) {
            // Re-index old NetEase-only cache files after TrackIdentity gained a player namespace.
            entries = Dictionary(value.map { ($0.value.document.track.normalizedKey, $0.value) }, uniquingKeysWith: { _, newer in newer })
        }
    }

    func document(for track: TrackIdentity) -> LyricsDocument? {
        guard var entry = entries[track.normalizedKey] else { return nil }
        entry.accessedAt = Date(); entries[track.normalizedKey] = entry
        return entry.document
    }

    func store(_ document: LyricsDocument) {
        entries[document.track.normalizedKey] = .init(document: document, accessedAt: Date())
        if entries.count > limit, let oldest = entries.min(by: { $0.value.accessedAt < $1.value.accessedAt })?.key { entries.removeValue(forKey: oldest) }
        if let data = try? JSONEncoder().encode(entries) { try? data.write(to: url, options: .atomic) }
    }
}

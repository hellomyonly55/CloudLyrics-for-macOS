import AppKit
import Foundation

@MainActor
final class AppViewModel: ObservableObject {
    private static let lyricsLookupTimeout: TimeInterval = 12
    @Published private(set) var snapshot = PlayerSnapshot(availability: .notRunning)
    @Published private(set) var document: LyricsDocument?
    @Published private(set) var message = "正在等待播放器…"
    @Published private(set) var isLoading = false
    @Published var settingsPresented = false

    private let player: PlayerAdapter
    private let providers: [LyricsProvider]
    private let cache = LyricsCache()
    private var timer: Timer?
    private var loadTask: Task<Void, Never>?
    private var currentKey: String?
    private var permissionRequested = false

    init(player: PlayerAdapter? = nil, providers: [LyricsProvider] = [KugouLocalLyricsProvider(), NetEaseLyricsProvider(), LRCLIBLyricsProvider()]) {
        self.player = player ?? AutomaticPlayerAdapter(); self.providers = providers
        let progressTimer = Timer(timeInterval: 0.10, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        progressTimer.tolerance = 0.02
        RunLoop.main.add(progressTimer, forMode: .common)
        timer = progressTimer
        refresh()
    }

    deinit { timer?.invalidate(); loadTask?.cancel() }

    func refresh(force: Bool = false) {
        snapshot = player.snapshot()
        switch snapshot.availability {
        case .permissionRequired:
            message = "酷狗歌词同步与控制需要辅助功能权限"
            if !permissionRequested { permissionRequested = true; player.requestPermission() }
        case .notRunning: message = "请先启动网易云音乐或酷狗音乐"
        case .connecting(let detail): message = detail
        case .incompatible(let detail): message = detail
        case .ready: break
        }
        guard let track = snapshot.track else { currentKey = nil; document = nil; return }
        let key = track.normalizedKey
        guard force || key != currentKey else { return }
        currentKey = key; document = nil; isLoading = true
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else { return }
            if !force, let cached = await cache.document(for: track) {
                guard !Task.isCancelled, currentKey == key else { return }
                document = cached; isLoading = false; return
            }
            let availableProviders = providers
            let result = await withTaskGroup(of: LyricsDocument?.self) { group in
                group.addTask {
                    for provider in availableProviders {
                        if Task.isCancelled { return nil }
                        if let document = try? await provider.lyrics(for: track) { return document }
                    }
                    return nil
                }
                group.addTask {
                    try? await Task.sleep(nanoseconds: UInt64(Self.lyricsLookupTimeout * 1_000_000_000))
                    return nil
                }
                let first = await group.next() ?? nil
                group.cancelAll()
                return first
            }
            guard !Task.isCancelled, currentKey == key else { return }
            if let result {
                await cache.store(result)
                document = result
                message = ""
            } else {
                message = "暂无歌词"
            }
            isLoading = false
        }
    }

    func requestPermission() { player.requestPermission() }
    func perform(_ command: PlayerCommand) {
        do { try player.perform(command); DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.refresh() } }
        catch { message = error.localizedDescription }
    }

    var currentLines: (String, String?) {
        guard let document, let index = document.lineIndex(at: snapshot.lyricProgress) else { return (isLoading ? "正在加载歌词…" : message, nil) }
        let presentation = LyricPresentation.make(document: document, index: index, mode: SettingsStoreReference.shared.appearance.mode)
        return (presentation.primary, presentation.secondary)
    }
}

@MainActor enum SettingsStoreReference { static let shared = SettingsStore() }

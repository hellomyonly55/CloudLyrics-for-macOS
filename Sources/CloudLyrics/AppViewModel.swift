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
        refresh()
    }

    deinit { timer?.invalidate(); loadTask?.cancel() }

    func refresh(force: Bool = false) {
        defer { scheduleNextRefresh() }
        let latestSnapshot = player.snapshot()
        if latestSnapshot != snapshot { snapshot = latestSnapshot }
        switch snapshot.availability {
        case .permissionRequired:
            setMessage("酷狗歌词同步与控制需要辅助功能权限")
            if !permissionRequested { permissionRequested = true; player.requestPermission() }
        case .notRunning: setMessage("请先启动网易云音乐或酷狗音乐")
        case .connecting(let detail): setMessage(detail)
        case .incompatible(let detail): setMessage(detail)
        case .ready: break
        }
        guard let track = snapshot.track else {
            if currentKey != nil { loadTask?.cancel() }
            currentKey = nil
            if document != nil { document = nil }
            if isLoading { isLoading = false }
            return
        }
        let key = track.normalizedKey
        guard force || key != currentKey else { return }
        currentKey = key
        if document != nil { document = nil }
        if !isLoading { isLoading = true }
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else { return }
            if !force, let cached = await cache.document(for: track) {
                guard !Task.isCancelled, currentKey == key else { return }
                document = cached
                if isLoading { isLoading = false }
                return
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
                setMessage("")
            } else {
                setMessage("暂无歌词")
            }
            if isLoading { isLoading = false }
        }
    }

    func requestPermission() { player.requestPermission() }
    func perform(_ command: PlayerCommand) {
        do { try player.perform(command); DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.refresh() } }
        catch { setMessage(error.localizedDescription) }
    }

    private func setMessage(_ value: String) {
        if message != value { message = value }
    }

    private func scheduleNextRefresh() {
        timer?.invalidate()
        let interval: TimeInterval
        if snapshot.isPlaying {
            // Five samples per second keeps time-synchronised lyrics responsive
            // without continuously polling player, process and audio state at 10 Hz.
            interval = 0.2
        } else {
            switch snapshot.availability {
            case .connecting: interval = 0.5
            case .ready: interval = 0.75
            case .permissionRequired, .notRunning, .incompatible: interval = 1.0
            }
        }
        let next = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        next.tolerance = min(0.1, interval * 0.2)
        RunLoop.main.add(next, forMode: .common)
        timer = next
    }

    var currentLines: (String, String?) {
        guard let document, let index = document.lineIndex(at: snapshot.lyricProgress) else { return (isLoading ? "正在加载歌词…" : message, nil) }
        let presentation = LyricPresentation.make(document: document, index: index, mode: SettingsStoreReference.shared.appearance.mode)
        return (presentation.primary, presentation.secondary)
    }
}

@MainActor enum SettingsStoreReference { static let shared = SettingsStore() }

import AppKit
import Combine
import Foundation

@MainActor
final class AppViewModel: ObservableObject {
    private static let lyricsLookupTimeout: TimeInterval = 12
    @Published private(set) var snapshot = PlayerSnapshot(availability: .notRunning)
    @Published private(set) var document: LyricsDocument?
    @Published private(set) var message = "正在等待播放器…"
    @Published private(set) var isLoading = false
    @Published var settingsPresented = false
    @Published private(set) var controlError: String?
    private var controlErrorTask: Task<Void, Never>?

    private let settings: SettingsStore
    private var settingsSubscription: AnyCancellable?
    private var lyricTimer: Timer?
    private var sampledAt = ProcessInfo.processInfo.systemUptime
    private let automaticallyRefresh: Bool
    private let player: PlayerAdapter
    private let providers: [LyricsProvider]
    private let cache = LyricsCache()
    private var timer: Timer?
    private var loadTask: Task<Void, Never>?
    private var currentKey: String?
    private var permissionRequested = false

    init(player: PlayerAdapter? = nil, providers: [LyricsProvider] = [KugouLocalLyricsProvider(), NetEaseLyricsProvider(), LRCLIBLyricsProvider()], settings: SettingsStore? = nil, automaticallyRefresh: Bool = true) {
        self.settings = settings ?? SettingsStoreReference.shared
        self.automaticallyRefresh = automaticallyRefresh
        self.player = player ?? AutomaticPlayerAdapter(); self.providers = providers
        settingsSubscription = self.settings.objectWillChange.sink { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.objectWillChange.send()
                self.scheduleNextRefresh()
                self.scheduleLyricBoundary()
            }
        }
        refresh()
    }

    deinit { timer?.invalidate(); lyricTimer?.invalidate(); loadTask?.cancel(); controlErrorTask?.cancel() }

    func refresh(force: Bool = false) {
        defer { scheduleNextRefresh(); scheduleLyricBoundary() }
        let latestSnapshot = player.snapshot()
        sampledAt = ProcessInfo.processInfo.systemUptime
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
                setMessage("")
                scheduleLyricBoundary()
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
                guard !Task.isCancelled, currentKey == key else { return }
                document = result
                scheduleLyricBoundary()
                setMessage("")
            } else {
                setMessage("暂无歌词")
            }
            if isLoading { isLoading = false }
        }
    }

    func requestPermission() { player.requestPermission() }
    func perform(_ command: PlayerCommand) {
        NSLog("CloudLyrics playback command: %@", String(describing: command))
        controlErrorTask?.cancel()
        controlError = nil
        do {
            try player.perform(command)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.refresh() }
        } catch {
            controlError = error.localizedDescription
            controlErrorTask = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: 5_000_000_000) } catch { return }
                self?.controlError = nil
            }
        }
    }

    private func setMessage(_ value: String) {
        if message != value { message = value }
    }

    private func scheduleNextRefresh() {
        timer?.invalidate()
        guard automaticallyRefresh else { return }
        let interval: TimeInterval
        if snapshot.isPlaying {
            interval = settings.synchronization.refreshMode.pollingInterval(
                lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled
            )
        } else {
            switch snapshot.availability {
            case .connecting: interval = 0.5
            case .ready: interval = 0.75
            case .permissionRequired, .incompatible: interval = 2.0
            case .notRunning: interval = 3.0
            }
        }
        let next = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        next.tolerance = min(0.1, interval * 0.2)
        RunLoop.main.add(next, forMode: .common)
        timer = next
    }

    // Interpolate in memory between player reads. A one-shot timer wakes only
    // when the next lyric is due, rather than reading AX/files more often.
    private var displayProgress: TimeInterval {
        var progress = snapshot.normalizedProgress
        if snapshot.isPlaying {
            progress += max(0, ProcessInfo.processInfo.systemUptime - sampledAt)
        }
        if let duration = snapshot.track?.duration, duration > 0 { progress = min(progress, duration) }
        return progress + settings.synchronization.lead(for: snapshot.player)
    }

    private func scheduleLyricBoundary() {
        lyricTimer?.invalidate()
        guard automaticallyRefresh, snapshot.isPlaying, let document else { return }
        if let duration = snapshot.track?.duration, duration > 0, snapshot.normalizedProgress >= duration { return }
        guard let delay = document.nextLineDelay(after: displayProgress) else { return }
        let next = Timer(timeInterval: max(0.001, delay), repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.objectWillChange.send()
                self.scheduleLyricBoundary()
            }
        }
        next.tolerance = 0.01
        RunLoop.main.add(next, forMode: .common)
        lyricTimer = next
    }

    var currentLines: (String, String?) {
        if let controlError { return (controlError, "右键歌词区域可打开设置") }
        guard let document else { return (isLoading ? "正在加载歌词…" : message, nil) }
        guard let index = document.lineIndex(at: displayProgress) else { return ("前奏…", nil) }
        let presentation = LyricPresentation.make(document: document, index: index, mode: settings.appearance.mode)
        return (presentation.primary, presentation.secondary)
    }
}

@MainActor enum SettingsStoreReference { static let shared = SettingsStore() }

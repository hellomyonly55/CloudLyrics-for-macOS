import AppKit
import Foundation

enum PlayerAvailability: Equatable {
    case ready, permissionRequired, notRunning, connecting(String), incompatible(String)
}

enum NetEaseConnectionState: Equatable {
    case checking, launching, restarting, waitingForCEF, connected, stopped, failed(String)
}

struct PlayerSnapshot: Equatable {
    static let kugouLyricLead: TimeInterval = 0.5

    var availability: PlayerAvailability
    var track: TrackIdentity?
    var progress: TimeInterval = 0
    var isPlaying = false
    var player: PlayerKind?

    var normalizedProgress: TimeInterval {
        guard let duration = track?.duration, duration > 0 else { return max(0, progress) }
        let positive = max(0, progress)
        if positive <= duration { return positive }
        return positive.truncatingRemainder(dividingBy: duration)
    }

    var lyricProgress: TimeInterval {
        normalizedProgress + (player == .kugou ? Self.kugouLyricLead : 0)
    }
}

enum PlayerCommand: Equatable { case previous, playPause, next }

enum NetEaseCEFCommand {
    static func selector(for command: PlayerCommand) -> String {
        switch command {
        case .previous: #"[data-log*='btn_pc_previous']"#
        case .playPause: "#btn_pc_minibar_play"
        case .next: #"[data-log*='btn_pc_next']"#
        }
    }

    static func expression(for command: PlayerCommand) -> String {
        let escaped = selector(for: command).replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
        return "(()=>{const button=document.querySelector('\(escaped)');if(!button)return JSON.stringify({commandError:'missing'});button.click();return JSON.stringify(window.__cloudLyricsPlayback)})()"
    }
}

@MainActor
protocol PlayerAdapter: AnyObject {
    var kind: PlayerKind? { get }
    var isRunning: Bool { get }
    func snapshot() -> PlayerSnapshot
    func perform(_ command: PlayerCommand) throws
    func requestPermission()
}

@MainActor
final class NetEaseAXPlayerAdapter: PlayerAdapter {
    private let bundleIdentifier = "com.netease.163music"
    private let localState = NetEaseLocalStateBridge()
    private let cefBridge = NetEaseCEFBridge()
    private let launchCoordinator = NetEaseLaunchCoordinator()

    let kind: PlayerKind? = .netease
    var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty }
    var connectionState: NetEaseConnectionState { launchCoordinator.state }

    func requestPermission() {
        // Background observation and control use NetEase's local CEF connection.
    }

    func snapshot() -> PlayerSnapshot {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        launchCoordinator.update(runningApplications: running, cefConnected: cefBridge.isConnected) { [weak self] in self?.cefBridge.invalidate() }
        guard !running.isEmpty else { return snapshotForConnectionState() }
        cefBridge.update()
        if let cefState = cefBridge.state {
            var snapshot = localState.snapshot(playback: cefState)
            snapshot.player = .netease
            return snapshot
        }
        return snapshotForConnectionState()
    }

    func perform(_ command: PlayerCommand) throws {
        guard NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first != nil else { throw AXPlayerError.notRunning }
        guard cefBridge.perform(command) else { throw AXPlayerError.controlUnavailable }
    }

    private func snapshotForConnectionState() -> PlayerSnapshot {
        switch launchCoordinator.state {
        case .checking: .init(availability: .connecting("正在检查网易云音乐…"), player: .netease)
        case .launching: .init(availability: .connecting("正在启动网易云音乐…"), player: .netease)
        case .restarting: .init(availability: .connecting("正在重新连接网易云音乐…"), player: .netease)
        case .waitingForCEF: .init(availability: .connecting("正在同步网易云播放状态…"), player: .netease)
        case .connected: .init(availability: .connecting("等待网易云播放事件…"), player: .netease)
        case .stopped: .init(availability: .notRunning, player: .netease)
        case .failed(let message): .init(availability: .incompatible(message), player: .netease)
        }
    }

}

enum NetEaseCEFEndpoint {
    static let host = "127.0.0.1"
    static let port = 9222
    static let discoveryURL = URL(string: "http://\(host):\(port)/json/list")!

    static func validatedWebSocketURL(from value: String) -> URL? {
        guard let url = URL(string: value),
              url.scheme?.lowercased() == "ws",
              url.host?.lowercased() == host,
              url.port == port else { return nil }
        return url
    }
}

private struct CEFPlaybackState {
    var songID: String
    var progress: TimeInterval
    var rate: Double
}

@MainActor
private final class NetEaseLaunchCoordinator {
    private let bundleIdentifier = "com.netease.163music"
    private let applicationURL = URL(fileURLWithPath: "/Applications/NeteaseMusic.app")
    private(set) var state: NetEaseConnectionState = .checking
    private var initialCheckHandled = false
    private var lastSawRunning = false
    private var probeDeadline: Date?
    private var cefDeadline: Date?
    private var operation: Task<Void, Never>?

    func update(runningApplications: [NSRunningApplication], cefConnected: Bool, invalidateCEF: @escaping () -> Void) {
        let isRunning = !runningApplications.isEmpty
        if cefConnected, isRunning {
            state = .connected; initialCheckHandled = true; lastSawRunning = true
            probeDeadline = nil; cefDeadline = nil
            return
        }
        if operation != nil { return }

        if !isRunning {
            invalidateCEF()
            if !initialCheckHandled {
                initialCheckHandled = true; lastSawRunning = false; state = .stopped
            } else if lastSawRunning {
                lastSawRunning = false; state = .stopped
            }
            return
        }

        if !initialCheckHandled || !lastSawRunning {
            initialCheckHandled = true; lastSawRunning = true
            state = .checking
            probeDeadline = Date().addingTimeInterval(1.5)
            return
        }

        if state == .waitingForCEF {
            if let cefDeadline, Date() < cefDeadline { return }
            state = .failed("网易云已启动，但调试连接超时")
            return
        }
        if let probeDeadline {
            guard Date() >= probeDeadline else { return }
            self.probeDeadline = nil
            invalidateCEF()
            startRestart(applications: runningApplications)
            return
        }
    }

    private func startRestart(applications: [NSRunningApplication]) {
        state = .restarting
        operation = Task { [weak self] in
            guard let self else { return }
            guard applications.allSatisfy({ $0.terminate() }) else {
                self.state = .failed("无法正常退出网易云音乐")
                self.operation = nil
                return
            }
            let deadline = Date().addingTimeInterval(8)
            while Date() < deadline, !NSRunningApplication.runningApplications(withBundleIdentifier: self.bundleIdentifier).isEmpty {
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            guard NSRunningApplication.runningApplications(withBundleIdentifier: self.bundleIdentifier).isEmpty else {
                self.state = .failed("等待网易云退出超时")
                self.operation = nil
                return
            }
            do {
                try await self.launchApplication()
                self.state = .waitingForCEF
                self.cefDeadline = Date().addingTimeInterval(12)
            } catch { self.state = .failed("重新启动网易云失败：\(error.localizedDescription)") }
            self.operation = nil
        }
    }

    private func launchApplication() async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = [
            "--remote-debugging-address=\(NetEaseCEFEndpoint.host)",
            "--remote-debugging-port=\(NetEaseCEFEndpoint.port)"
        ]
        configuration.activates = false
        _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<NSRunningApplication, Error>) in
            NSWorkspace.shared.openApplication(at: applicationURL, configuration: configuration) { application, error in
                if let application { continuation.resume(returning: application) }
                else { continuation.resume(throwing: error ?? AXPlayerError.notRunning) }
            }
        }
    }
}

@MainActor
private final class NetEaseCEFBridge {
    private var socket: URLSessionWebSocketTask?
    private var connecting = false
    private var requestPending = false
    private var nextID = 1
    private var queuedCommand: PlayerCommand?
    private(set) var state: CEFPlaybackState?
    var isConnected: Bool { socket != nil }

    func invalidate() { reset() }

    func update() {
        guard socket != nil else { connect(); return }
        guard !requestPending else { return }
        let expression = #"(()=>{if(!window.__cloudLyricsRequire){const id=987654;webpackJsonp.push([[id],{[id]:(m,e,r)=>window.__cloudLyricsRequire=r},[[id]]])}if(!window.__cloudLyricsProgressSub){window.__cloudLyricsPlayback=null;const m=window.__cloudLyricsRequire(1126);window.__cloudLyricsProgressSub=m.audioPlayerPlayProgress$.subscribe(v=>window.__cloudLyricsPlayback={songID:String(v[0]),progress:Number(v[1]),rate:Number(v[2])})}return JSON.stringify(window.__cloudLyricsPlayback)})()"#
        evaluate(expression)
    }

    func perform(_ command: PlayerCommand) -> Bool {
        guard socket != nil else { return false }
        guard !requestPending else { queuedCommand = command; return true }
        evaluate(NetEaseCEFCommand.expression(for: command))
        return true
    }

    private func connect() {
        guard !connecting else { return }
        connecting = true
        URLSession.shared.dataTask(with: NetEaseCEFEndpoint.discoveryURL) { [weak self] data, _, _ in
            guard let data,
                  let pages = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let value = pages.first?["webSocketDebuggerUrl"] as? String,
                  let socketURL = NetEaseCEFEndpoint.validatedWebSocketURL(from: value) else {
                Task { @MainActor in self?.connecting = false }
                return
            }
            Task { @MainActor in
                guard let self else { return }
                let task = URLSession.shared.webSocketTask(with: socketURL)
                self.socket = task; self.connecting = false; task.resume(); self.update()
            }
        }.resume()
    }

    private func evaluate(_ expression: String) {
        guard let socket else { return }
        let id = nextID; nextID += 1; requestPending = true
        let payload: [String: Any] = ["id": id, "method": "Runtime.evaluate", "params": ["expression": expression, "returnByValue": true, "awaitPromise": true]]
        guard let data = try? JSONSerialization.data(withJSONObject: payload), let text = String(data: data, encoding: .utf8) else { requestPending = false; return }
        socket.send(.string(text)) { [weak self] error in
            if error != nil { Task { @MainActor in self?.reset() } }
        }
        receive(responseID: id)
    }

    private func receive(responseID: Int) {
        socket?.receive { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .failure: self.reset()
                case .success(let message):
                    let data: Data
                    switch message { case .string(let text): data = Data(text.utf8); case .data(let value): data = value; @unknown default: self.reset(); return }
                    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { self.receive(responseID: responseID); return }
                    guard (root["id"] as? NSNumber)?.intValue == responseID else { self.receive(responseID: responseID); return }
                    self.requestPending = false
                    if let result = root["result"] as? [String: Any], let inner = result["result"] as? [String: Any], let value = inner["value"] as? String, let json = value.data(using: .utf8), let state = try? JSONSerialization.jsonObject(with: json) as? [String: Any], let songID = state["songID"] as? String, let progress = state["progress"] as? NSNumber, let rate = state["rate"] as? NSNumber {
                        self.state = .init(songID: songID, progress: progress.doubleValue, rate: rate.doubleValue)
                    }
                    if let command = self.queuedCommand {
                        self.queuedCommand = nil
                        _ = self.perform(command)
                    }
                }
            }
        }
    }

    private func reset() { socket?.cancel(); socket = nil; connecting = false; requestPending = false; queuedCommand = nil; state = nil }
}

/// Reads the song id from the audio cache file currently held open by the
/// NetEase process, then resolves its metadata from NetEase's local play queue.
/// This works in the background and does not depend on window accessibility.
@MainActor
private final class NetEaseLocalStateBridge {
    private var currentTrack: TrackIdentity?
    private var loadingSongID: String?

    func snapshot(playback: CEFPlaybackState) -> PlayerSnapshot {
        if currentTrack?.sourceID != playback.songID {
            currentTrack = .init(title: "正在获取歌曲信息…", artist: "网易云音乐", sourceID: playback.songID)
            loadMetadata(songID: playback.songID)
        }
        return .init(availability: .ready, track: currentTrack, progress: playback.progress, isPlaying: playback.rate > 0)
    }

    private func loadMetadata(songID: String) {
        guard loadingSongID != songID else { return }
        loadingSongID = songID
        var components = URLComponents(string: "https://music.163.com/api/song/detail/")!
        components.queryItems = [.init(name: "id", value: songID), .init(name: "ids", value: "[\(songID)]")]
        var request = URLRequest(url: components.url!, timeoutInterval: 8)
        request.setValue("https://music.163.com/", forHTTPHeaderField: "Referer")
        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let data,
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let song = (root["songs"] as? [[String: Any]])?.first else { return }
            let title = song["name"] as? String ?? "未知歌曲"
            let artists = (song["artists"] as? [[String: Any]])?.compactMap { $0["name"] as? String }.joined(separator: " / ") ?? "未知歌手"
            let duration = (song["duration"] as? NSNumber).map { $0.doubleValue / 1000 }
            Task { @MainActor in
                guard let self, self.currentTrack?.sourceID == songID else { return }
                self.currentTrack = .init(title: title, artist: artists, duration: duration, sourceID: songID)
                self.loadingSongID = nil
            }
        }.resume()
    }
}

enum AXPlayerError: LocalizedError {
    case permissionRequired, notRunning, controlUnavailable
    var errorDescription: String? {
        switch self {
        case .permissionRequired: "需要辅助功能权限"
        case .notRunning: "当前播放器尚未运行"
        case .controlUnavailable: "当前播放器暂时无法执行此控制"
        }
    }
}

import Foundation
import ServiceManagement

@MainActor
final class SettingsStore: ObservableObject {
    @Published var appearance: AppearanceSettings { didSet { save() } }
    @Published var synchronization: SynchronizationSettings { didSet {
        if let data = try? JSONEncoder().encode(synchronization) {
            defaults.set(data, forKey: "synchronization.v1")
        }
    } }
    @Published private(set) var launchAtLogin = false
    @Published private(set) var launchAtLoginError: String?
    private let defaults: UserDefaults
    private let key = "appearance.v2"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key), let value = try? JSONDecoder().decode(AppearanceSettings.self, from: data) { appearance = value }
        else { appearance = .defaults }
        if let data = defaults.data(forKey: "synchronization.v1"),
           let value = try? JSONDecoder().decode(SynchronizationSettings.self, from: data) {
            synchronization = value
        } else { synchronization = .defaults }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func reset() { appearance = .defaults }

    func resetSynchronization() { synchronization = .defaults }

    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLoginError = nil
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            if enabled, !launchAtLogin {
                launchAtLoginError = "请在系统设置 → 通用 → 登录项中允许 CloudLyrics。"
            }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            launchAtLoginError = "无法更改登录启动：\(error.localizedDescription)"
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(appearance) { defaults.set(data, forKey: key) }
    }
}

import Foundation
import ServiceManagement

@MainActor
final class SettingsStore: ObservableObject {
    @Published var appearance: AppearanceSettings { didSet { save() } }
    @Published private(set) var launchAtLogin = false
    private let defaults: UserDefaults
    private let key = "appearance.v2"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key), let value = try? JSONDecoder().decode(AppearanceSettings.self, from: data) { appearance = value }
        else { appearance = .defaults }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func reset() { appearance = .defaults }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
        } catch { launchAtLogin = SMAppService.mainApp.status == .enabled }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(appearance) { defaults.set(data, forKey: key) }
    }
}

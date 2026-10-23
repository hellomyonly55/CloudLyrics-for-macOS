import XCTest
@testable import CloudLyrics

@MainActor
final class SettingsTests: XCTestCase {
    func testPersistenceAndReset() {
        let name = "CloudLyricsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults)
        store.appearance.width = 612
        let restored = SettingsStore(defaults: defaults)
        XCTAssertEqual(restored.appearance.width, 612)
        restored.reset()
        XCTAssertEqual(restored.appearance, .defaults)
    }
    func testSynchronizationPersistsSeparatelyFromAppearance() {
        let name = "CloudLyricsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults)
        store.appearance.width = 612
        store.synchronization.neteaseLead = -1.2
        store.synchronization.kugouLead = 0.8
        store.synchronization.refreshMode = .energySaving
        let restored = SettingsStore(defaults: defaults)
        XCTAssertEqual(restored.synchronization, store.synchronization)
        XCTAssertEqual(restored.synchronization.lead(for: .netease), -1.2)
        XCTAssertEqual(restored.synchronization.lead(for: .kugou), 0.8)
        restored.reset()
        XCTAssertEqual(restored.synchronization.neteaseLead, -1.2)
        restored.resetSynchronization()
        XCTAssertEqual(restored.synchronization, .defaults)
    }

    func testExistingAppearanceWithoutSynchronizationLoadsDefaults() throws {
        let name = "CloudLyricsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        var appearance = AppearanceSettings.defaults
        appearance.primarySize = 11
        defaults.set(try JSONEncoder().encode(appearance), forKey: "appearance.v2")
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.appearance.primarySize, 11)
        XCTAssertEqual(store.synchronization, .defaults)
    }

}

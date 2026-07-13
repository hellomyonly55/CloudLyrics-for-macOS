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
}

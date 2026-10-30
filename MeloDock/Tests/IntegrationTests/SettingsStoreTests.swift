#if canImport(XCTest)
import XCTest
@testable import MeloDock

final class SettingsStoreTests: XCTestCase {
    @MainActor
    func testPersistsProviderAndLaunchAtLoginFlag() {
        let suiteName = "SettingsStoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Could not create isolated UserDefaults suite")
            return
        }

        defaults.removePersistentDomain(forName: suiteName)

        let store = SettingsStore(defaults: defaults)
        store.preferredProvider = .spotify
        store.launchAtLogin = true

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.preferredProvider, .spotify)
        XCTAssertTrue(reloaded.launchAtLogin)

        defaults.removePersistentDomain(forName: suiteName)
    }

    @MainActor
    func testOverlayVisibleAlwaysStartsFalse() {
        let suiteName = "SettingsStoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Could not create isolated UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(true, forKey: "settings.overlayVisible")

        let store = SettingsStore(defaults: defaults)
        XCTAssertFalse(store.overlayVisible)

        defaults.removePersistentDomain(forName: suiteName)
    }

    @MainActor
    func testShowOnStartupDefaultsToTrue() {
        let suiteName = "SettingsStoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Could not create isolated UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)

        let store = SettingsStore(defaults: defaults)
        XCTAssertTrue(store.showOnStartup)

        defaults.removePersistentDomain(forName: suiteName)
    }
}
#endif

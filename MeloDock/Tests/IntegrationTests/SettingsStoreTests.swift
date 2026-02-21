#if canImport(XCTest)
import XCTest
@testable import MeloDock

final class SettingsStoreTests: XCTestCase {
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
}
#endif

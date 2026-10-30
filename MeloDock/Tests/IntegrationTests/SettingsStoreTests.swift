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

    @MainActor
    func testIslandActivityTogglesDefaultToTrue() {
        let suiteName = "SettingsStoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Could not create isolated UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)

        let store = SettingsStore(defaults: defaults)
        XCTAssertTrue(store.showPower)
        XCTAssertTrue(store.showAudio)
        XCTAssertTrue(store.showCapture)

        defaults.removePersistentDomain(forName: suiteName)
    }

    @MainActor
    func testIslandActivityTogglesPersistUnderTheirKeys() {
        let suiteName = "SettingsStoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Could not create isolated UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)

        let store = SettingsStore(defaults: defaults)
        store.showPower = false
        store.showAudio = false
        store.showCapture = false
        XCTAssertEqual(defaults.object(forKey: "settings.island.power") as? Bool, false)
        XCTAssertEqual(defaults.object(forKey: "settings.island.audio") as? Bool, false)
        XCTAssertEqual(defaults.object(forKey: "settings.island.capture") as? Bool, false)

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertFalse(reloaded.showPower)
        XCTAssertFalse(reloaded.showAudio)
        XCTAssertFalse(reloaded.showCapture)

        defaults.removePersistentDomain(forName: suiteName)
    }

    @MainActor
    func testTimerDefaultsOnAndCalendarDefaultsOff() {
        let suiteName = "SettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults)
        XCTAssertTrue(store.showTimer)
        XCTAssertFalse(store.showCalendar)
    }

    @MainActor
    func testTimerAndCalendarPersistUnderTheirKeys() {
        let suiteName = "SettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults)
        store.showTimer = false
        store.showCalendar = true
        XCTAssertEqual(defaults.object(forKey: "settings.island.timer") as? Bool, false)
        XCTAssertEqual(defaults.object(forKey: "settings.island.calendar") as? Bool, true)

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertFalse(reloaded.showTimer)
        XCTAssertTrue(reloaded.showCalendar)
    }
}
#endif

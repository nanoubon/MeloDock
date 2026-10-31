import XCTest
@testable import MeloDock

@MainActor
final class SpotifyProviderKeychainTests: XCTestCase {
    private final class SpyKeychain: KeychainService {
        private(set) var reads = 0

        override func data(for key: String) -> Data? {
            reads += 1
            return nil
        }
    }

    func testInitDoesNotReadKeychain() {
        let suite = "SpotifyProviderKeychainTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let keychain = SpyKeychain()

        let provider = SpotifyProvider(settingsStore: SettingsStore(defaults: defaults), keychainService: keychain)

        XCTAssertEqual(keychain.reads, 0)
        XCTAssertEqual(provider.authState, .unauthorized)
    }

    func testRefreshReadsKeychainAndReportsUnauthorizedWithoutToken() async {
        let suite = "SpotifyProviderKeychainTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let keychain = SpyKeychain()
        let provider = SpotifyProvider(settingsStore: SettingsStore(defaults: defaults), keychainService: keychain)

        await provider.refreshNowPlaying()

        XCTAssertEqual(keychain.reads, 1)
        XCTAssertEqual(provider.authState, .unauthorized)
    }
}

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

extension SpotifyProviderKeychainTests {
    func testTokenIsReadFromKeychainOnlyOnceAcrossRefreshes() async throws {
        let suite = "SpotifyProviderKeychainTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        // SpotifyToken is private, so mirror its Codable shape (Date encodes as reference-date seconds).
        let json: [String: Any] = [
            "accessToken": "a",
            "refreshToken": "r",
            "expiresAt": Date().addingTimeInterval(3600).timeIntervalSinceReferenceDate
        ]
        let keychain = TokenKeychain(data: try JSONSerialization.data(withJSONObject: json))
        let provider = SpotifyProvider(
            settingsStore: SettingsStore(defaults: defaults),
            keychainService: keychain,
            session: URLSession(configuration: {
                let c = URLSessionConfiguration.ephemeral
                c.protocolClasses = [FailingURLProtocol.self]
                return c
            }())
        )

        await provider.refreshNowPlaying()
        await provider.refreshNowPlaying()
        await provider.refreshNowPlaying()

        XCTAssertEqual(keychain.reads, 1)
    }

    private final class TokenKeychain: KeychainService {
        private let stored: Data
        private(set) var reads = 0
        init(data: Data) { stored = data }
        override func data(for key: String) -> Data? {
            reads += 1
            return stored
        }
    }

    private final class FailingURLProtocol: URLProtocol {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)) }
        override func stopLoading() {}
    }
}

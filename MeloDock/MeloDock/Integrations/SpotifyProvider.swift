import AppKit
import AuthenticationServices
import Combine
import CryptoKit
import Foundation

@MainActor
final class SpotifyProvider: NSObject, MusicProvider, ASWebAuthenticationPresentationContextProviding {
    let kind: MusicProviderKind = .spotify

    private let settingsStore: SettingsStore
    private let keychainService: KeychainService
    private let session: URLSession

    private let playbackSubject = CurrentValueSubject<PlaybackState, Never>(
        .unavailable(provider: .spotify, message: "Connect Spotify in Settings.")
    )
    private let authSubject = CurrentValueSubject<ProviderAuthState, Never>(.unauthorized)

    private var authSession: ASWebAuthenticationSession?
    private var pendingCodeVerifier: String?
    private var pendingState: String?

    private var cachedIsPlaying = false
    private let tokenKey = "spotify.oauth.token"

    var authState: ProviderAuthState { authSubject.value }
    var authStatePublisher: AnyPublisher<ProviderAuthState, Never> { authSubject.eraseToAnyPublisher() }
    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> { playbackSubject.eraseToAnyPublisher() }

    init(
        settingsStore: SettingsStore,
        keychainService: KeychainService,
        session: URLSession = .shared
    ) {
        self.settingsStore = settingsStore
        self.keychainService = keychainService
        self.session = session
        super.init()

        if loadToken() != nil {
            authSubject.send(.authorized)
        }
    }

    func authorize() async {
        guard !settingsStore.spotifyClientID.isEmpty else {
            authSubject.send(.unavailable("Spotify Client ID is missing."))
            playbackSubject.send(.unavailable(
                provider: .spotify,
                message: "Add a Spotify Client ID in Settings first."
            ))
            return
        }

        let verifier = Self.randomString(length: 96)
        let challenge = Self.codeChallenge(for: verifier)
        let state = Self.randomString(length: 24)

        pendingCodeVerifier = verifier
        pendingState = state

        guard let url = authorizationURL(challenge: challenge, state: state) else {
            authSubject.send(.unavailable("Failed to build Spotify authorization URL."))
            return
        }

        startAuthSession(url: url)
    }

    func refreshNowPlaying() async {
        await refreshNowPlaying(allowTokenRetry: true)
    }

    private func refreshNowPlaying(allowTokenRetry: Bool) async {
        do {
            let token = try await ensureValidAccessToken()

            var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/player")!)
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw SpotifyError.invalidResponse
            }

            if http.statusCode == 204 {
                cachedIsPlaying = false
                playbackSubject.send(PlaybackState(
                    provider: .spotify,
                    status: .stopped,
                    track: nil,
                    message: "No active Spotify playback."
                ))
                return
            }

            if http.statusCode == 401 {
                guard allowTokenRetry else {
                    authSubject.send(.unauthorized)
                    playbackSubject.send(.unavailable(
                        provider: .spotify,
                        message: Self.errorMessage(for: 401)
                    ))
                    return
                }
                _ = try await refreshAccessToken()
                await refreshNowPlaying(allowTokenRetry: false)
                return
            }

            guard (200..<300).contains(http.statusCode) else {
                playbackSubject.send(.unavailable(
                    provider: .spotify,
                    message: Self.errorMessage(for: http.statusCode)
                ))
                return
            }

            let payload = try JSONDecoder().decode(SpotifyPlaybackPayload.self, from: data)
            cachedIsPlaying = payload.is_playing

            let track = payload.item.map { item in
                let artworkURL = item.album?.images.first?.url
                    ?? item.images?.first?.url
                    ?? item.show?.images.first?.url

                let artist: String
                if let artists = item.artists, artists.isEmpty == false {
                    artist = artists.map(\.name).joined(separator: ", ")
                } else {
                    artist = item.show?.name ?? "Unknown Artist"
                }

                return Track(
                    id: item.id ?? UUID().uuidString,
                    title: item.name,
                    artist: artist,
                    artworkURL: artworkURL.flatMap(URL.init(string:)),
                    duration: TimeInterval(item.duration_ms) / 1000,
                    progress: TimeInterval(payload.progress_ms ?? 0) / 1000
                )
            }

            playbackSubject.send(
                PlaybackState(
                    provider: .spotify,
                    status: payload.is_playing ? .playing : .paused,
                    track: track,
                    message: track == nil ? "No active Spotify track." : nil
                )
            )

            authSubject.send(.authorized)
        } catch SpotifyError.missingToken {
            authSubject.send(.unauthorized)
            playbackSubject.send(.unavailable(provider: .spotify, message: "Spotify is not connected."))
        } catch {
            playbackSubject.send(.unavailable(provider: .spotify, message: error.localizedDescription))
        }
    }

    func togglePlayPause() async {
        let endpoint = cachedIsPlaying ? "pause" : "play"

        do {
            try await sendCommand(path: endpoint, method: "PUT")
            await refreshNowPlaying()
        } catch {
            playbackSubject.send(.unavailable(provider: .spotify, message: error.localizedDescription))
        }
    }

    func playNext() async {
        do {
            try await sendCommand(path: "next", method: "POST")
            await refreshNowPlaying()
        } catch {
            playbackSubject.send(.unavailable(provider: .spotify, message: error.localizedDescription))
        }
    }

    func playPrevious() async {
        do {
            try await sendCommand(path: "previous", method: "POST")
            await refreshNowPlaying()
        } catch {
            playbackSubject.send(.unavailable(provider: .spotify, message: error.localizedDescription))
        }
    }

    func clearSession() throws {
        try keychainService.removeValue(for: tokenKey)
        authSubject.send(.unauthorized)
        playbackSubject.send(.unavailable(provider: .spotify, message: "Spotify session cleared."))
    }

    func handleIncomingAuthURL(_ url: URL) {
        Task { await handleAuthCallback(url: url) }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSApp.mainWindow ?? ASPresentationAnchor()
    }

    private func authorizationURL(challenge: String, state: String) -> URL? {
        var components = URLComponents(string: "https://accounts.spotify.com/authorize")
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: settingsStore.spotifyClientID),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(
                name: "scope",
                value: "user-read-playback-state user-read-currently-playing user-modify-playback-state"
            )
        ]
        return components?.url
    }

    private func startAuthSession(url: URL) {
        let session = ASWebAuthenticationSession(
            url: url,
            callbackURLScheme: "melodock"
        ) { [weak self] callbackURL, error in
            Task { @MainActor in
                guard let self else { return }

                if let error {
                    self.authSubject.send(.unavailable(error.localizedDescription))
                    return
                }

                guard let callbackURL else {
                    self.authSubject.send(.unavailable("Spotify callback URL was missing."))
                    return
                }

                await self.handleAuthCallback(url: callbackURL)
            }
        }

        session.prefersEphemeralWebBrowserSession = true
        session.presentationContextProvider = self
        authSession = session

        if !session.start() {
            authSubject.send(.unavailable("Could not start Spotify authentication session."))
        }
    }

    private func handleAuthCallback(url: URL) async {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            authSubject.send(.unavailable("Invalid Spotify callback URL."))
            return
        }

        let query = HTTPFormCoding.queryDictionary(from: components.queryItems)

        if let returnedError = query["error"] {
            authSubject.send(.unavailable("Spotify auth failed: \(returnedError)"))
            return
        }

        guard let code = query["code"], !code.isEmpty else {
            authSubject.send(.unavailable("Spotify auth code was missing."))
            return
        }

        guard let state = query["state"], state == pendingState else {
            authSubject.send(.unavailable("Spotify auth state mismatch."))
            return
        }

        guard let verifier = pendingCodeVerifier else {
            authSubject.send(.unavailable("PKCE verifier missing."))
            return
        }

        do {
            let token = try await exchangeCodeForToken(code: code, verifier: verifier)
            try saveToken(token)
            authSubject.send(.authorized)
            await refreshNowPlaying()
        } catch {
            authSubject.send(.unavailable("Token exchange failed: \(error.localizedDescription)"))
        }

        pendingCodeVerifier = nil
        pendingState = nil
    }

    private func exchangeCodeForToken(code: String, verifier: String) async throws -> SpotifyToken {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = HTTPFormCoding.encode([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": Self.redirectURI,
            "client_id": settingsStore.spotifyClientID,
            "code_verifier": verifier
        ])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SpotifyError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw SpotifyError.httpStatus(code: http.statusCode)
        }

        let payload = try JSONDecoder().decode(SpotifyTokenPayload.self, from: data)
        guard let refreshToken = payload.refresh_token else {
            throw SpotifyError.invalidResponse
        }

        return SpotifyToken(
            accessToken: payload.access_token,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(payload.expires_in))
        )
    }

    private func refreshAccessToken() async throws -> SpotifyToken {
        guard let existingToken = loadToken() else {
            throw SpotifyError.missingToken
        }

        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = HTTPFormCoding.encode([
            "grant_type": "refresh_token",
            "refresh_token": existingToken.refreshToken,
            "client_id": settingsStore.spotifyClientID
        ])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SpotifyError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw SpotifyError.httpStatus(code: http.statusCode)
        }

        let payload = try JSONDecoder().decode(SpotifyTokenPayload.self, from: data)
        let refreshed = SpotifyToken(
            accessToken: payload.access_token,
            refreshToken: payload.refresh_token ?? existingToken.refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(payload.expires_in))
        )

        try saveToken(refreshed)
        authSubject.send(.authorized)
        return refreshed
    }

    private func ensureValidAccessToken() async throws -> String {
        guard let token = loadToken() else {
            throw SpotifyError.missingToken
        }

        if token.isExpired {
            let refreshed = try await refreshAccessToken()
            return refreshed.accessToken
        }

        return token.accessToken
    }

    private func sendCommand(path: String, method: String, allowTokenRetry: Bool = true) async throws {
        let token = try await ensureValidAccessToken()

        var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/player/\(path)")!)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SpotifyError.invalidResponse
        }

        if http.statusCode == 401 {
            guard allowTokenRetry else {
                throw SpotifyError.httpStatus(code: 401)
            }
            _ = try await refreshAccessToken()
            try await sendCommand(path: path, method: method, allowTokenRetry: false)
            return
        }

        guard (200..<300).contains(http.statusCode) || http.statusCode == 204 else {
            throw SpotifyError.httpStatus(code: http.statusCode)
        }
    }

    private func saveToken(_ token: SpotifyToken) throws {
        let data = try JSONEncoder().encode(token)
        try keychainService.set(data: data, for: tokenKey)
    }

    private func loadToken() -> SpotifyToken? {
        guard let data = keychainService.data(for: tokenKey) else { return nil }
        return try? JSONDecoder().decode(SpotifyToken.self, from: data)
    }

    private static let redirectURI = "melodock://spotify-auth"

    private static func randomString(length: Int) -> String {
        let characters = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return String((0..<length).map { _ in characters.randomElement() ?? "a" })
    }

    private static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        let base64 = Data(digest).base64EncodedString()
        return base64
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    nonisolated fileprivate static func errorMessage(for statusCode: Int) -> String {
        switch statusCode {
        case 401:
            return "Spotify authorization expired. Reconnect in Settings."
        case 403:
            return "Spotify playback control requires a Premium account."
        case 404:
            return "No active Spotify device. Start playback in Spotify first."
        default:
            return "Spotify request failed (\(statusCode))."
        }
    }
}

private enum SpotifyError: LocalizedError {
    case missingToken
    case invalidResponse
    case httpStatus(code: Int)

    var errorDescription: String? {
        switch self {
        case .missingToken:
            return "Spotify is not connected."
        case .invalidResponse:
            return "Spotify returned an invalid response."
        case .httpStatus(let code):
            return SpotifyProvider.errorMessage(for: code)
        }
    }
}

private struct SpotifyToken: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date

    var isExpired: Bool {
        Date().addingTimeInterval(30) >= expiresAt
    }
}

private struct SpotifyTokenPayload: Codable {
    let access_token: String
    let token_type: String
    let scope: String?
    let expires_in: Int
    let refresh_token: String?
}

private struct SpotifyPlaybackPayload: Codable {
    let is_playing: Bool
    let progress_ms: Int?
    let item: SpotifyTrackPayload?
}

private struct SpotifyTrackPayload: Codable {
    let id: String?
    let name: String
    let duration_ms: Int
    let type: String?
    let artists: [SpotifyArtistPayload]?
    let album: SpotifyAlbumPayload?
    let images: [SpotifyImagePayload]?
    let show: SpotifyShowPayload?
}

private struct SpotifyShowPayload: Codable {
    let name: String?
    let images: [SpotifyImagePayload]?
}

private struct SpotifyArtistPayload: Codable {
    let name: String
}

private struct SpotifyAlbumPayload: Codable {
    let images: [SpotifyImagePayload]
}

private struct SpotifyImagePayload: Codable {
    let url: String
}

import Combine
import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var preferredProvider: MusicProviderKind
    @Published var showOnStartup: Bool
    @Published var launchAtLogin: Bool
    @Published var spotifyClientID: String

    @Published private(set) var appleMusicAuthState: ProviderAuthState = .unknown
    @Published private(set) var spotifyAuthState: ProviderAuthState = .unknown
    @Published private(set) var launchAtLoginStatusText: String = "Unknown"
    @Published private(set) var isProUnlocked: Bool = false
    @Published private(set) var statusInfoText: String?
    @Published private(set) var errorText: String?

    private let settingsStore: SettingsStore
    private let launchAtLoginService: LaunchAtLoginService
    private let musicProviders: [MusicProviderKind: MusicProvider]
    private let spotifyProvider: SpotifyProvider
    private let proFeatureService: ProFeatureService

    private var cancellables = Set<AnyCancellable>()

    init(
        settingsStore: SettingsStore,
        launchAtLoginService: LaunchAtLoginService,
        musicProviders: [MusicProviderKind: MusicProvider],
        spotifyProvider: SpotifyProvider,
        proFeatureService: ProFeatureService
    ) {
        self.settingsStore = settingsStore
        self.launchAtLoginService = launchAtLoginService
        self.musicProviders = musicProviders
        self.spotifyProvider = spotifyProvider
        self.proFeatureService = proFeatureService

        preferredProvider = settingsStore.preferredProvider
        showOnStartup = settingsStore.showOnStartup
        launchAtLogin = settingsStore.launchAtLogin
        spotifyClientID = settingsStore.spotifyClientID

        bindSettings()
        bindServices()

        Task {
            await refreshProviderStates()
            await proFeatureService.refresh()
        }
    }

    var hotkeyDescription: String {
        settingsStore.hotkey.displayName
    }

    func authorizeAppleMusic() {
        Task {
            await musicProviders[.appleMusic]?.authorize()
            await refreshProviderStates()
        }
    }

    func authorizeSpotify() {
        Task {
            await spotifyProvider.authorize()
            await refreshProviderStates()
        }
    }

    func clearSpotifySession() {
        do {
            try spotifyProvider.clearSession()
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }

        Task { await refreshProviderStates() }
    }

    func resetHotkey() {
        settingsStore.hotkey = .default
    }

    func refreshProStatus() {
        Task { await proFeatureService.refresh() }
    }

    private func bindSettings() {
        $preferredProvider
            .dropFirst()
            .sink { [weak self] provider in
                self?.settingsStore.preferredProvider = provider
            }
            .store(in: &cancellables)

        $showOnStartup
            .dropFirst()
            .sink { [weak self] value in
                self?.settingsStore.showOnStartup = value
            }
            .store(in: &cancellables)

        $launchAtLogin
            .dropFirst()
            .sink { [weak self] value in
                self?.settingsStore.launchAtLogin = value
                self?.launchAtLoginService.setEnabled(value)
                if value == false {
                    self?.statusInfoText = nil
                    self?.errorText = nil
                }
            }
            .store(in: &cancellables)

        $spotifyClientID
            .dropFirst()
            .sink { [weak self] clientID in
                self?.settingsStore.spotifyClientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .store(in: &cancellables)
    }

    private func bindServices() {
        launchAtLoginService.$isEnabled
            .sink { [weak self] enabled in
                self?.launchAtLoginStatusText = enabled ? "Enabled" : "Disabled"
            }
            .store(in: &cancellables)

        launchAtLoginService.$lastError
            .sink { [weak self] error in
                guard let self else { return }
                guard let error else {
                    self.statusInfoText = nil
                    self.errorText = nil
                    return
                }

                if self.isInformationalLaunchAtLoginMessage(error) {
                    self.statusInfoText = error
                    self.errorText = nil
                } else {
                    self.statusInfoText = nil
                    self.errorText = error
                }
            }
            .store(in: &cancellables)

        musicProviders[.appleMusic]?.authStatePublisher
            .sink { [weak self] state in
                self?.appleMusicAuthState = state
            }
            .store(in: &cancellables)

        musicProviders[.spotify]?.authStatePublisher
            .sink { [weak self] state in
                self?.spotifyAuthState = state
            }
            .store(in: &cancellables)

        proFeatureService.isProPublisher
            .sink { [weak self] isPro in
                self?.isProUnlocked = isPro
            }
            .store(in: &cancellables)
    }

    private func refreshProviderStates() async {
        await musicProviders[.appleMusic]?.refreshNowPlaying()
        await musicProviders[.spotify]?.refreshNowPlaying()
    }

    private func isInformationalLaunchAtLoginMessage(_ message: String) -> Bool {
        let normalized = message.lowercased()
        return normalized.contains("launch at login")
            && (normalized.contains("debug")
                || normalized.contains("signed")
                || normalized.contains("/applications")
                || normalized.contains("operation not permitted"))
    }
}

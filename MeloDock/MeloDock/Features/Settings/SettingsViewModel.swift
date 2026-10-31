import AppKit
import Combine
import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var preferredProvider: MusicProviderKind
    @Published var showOnStartup: Bool
    @Published var launchAtLogin: Bool
    @Published var spotifyClientID: String
    @Published var showPower: Bool
    @Published var showAudio: Bool
    @Published var showCapture: Bool
    @Published var showTimer: Bool
    @Published var showNetwork: Bool
    @Published var showLiveSpectrum: Bool
    @Published private(set) var spectrumStatus: SpectrumStatus = .off
    /// Changed only through `setCalendarEnabled`, so it never turns on without permission.
    @Published private(set) var showCalendar: Bool
    @Published private(set) var calendarAccessDenied = false

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
    private let calendarAccess: CalendarAccessProviding
    private let openURL: (URL) -> Void

    private let notificationCenter: NotificationCenter
    private var cancellables = Set<AnyCancellable>()

    init(
        settingsStore: SettingsStore,
        launchAtLoginService: LaunchAtLoginService,
        musicProviders: [MusicProviderKind: MusicProvider],
        spotifyProvider: SpotifyProvider,
        proFeatureService: ProFeatureService,
        calendarAccess: CalendarAccessProviding,
        spectrumStatus: AnyPublisher<SpectrumStatus, Never> = Just(.off).eraseToAnyPublisher(),
        openURL: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) },
        notificationCenter: NotificationCenter = .default
    ) {
        self.settingsStore = settingsStore
        self.launchAtLoginService = launchAtLoginService
        self.musicProviders = musicProviders
        self.spotifyProvider = spotifyProvider
        self.proFeatureService = proFeatureService
        self.calendarAccess = calendarAccess
        self.openURL = openURL
        self.notificationCenter = notificationCenter

        preferredProvider = settingsStore.preferredProvider
        showOnStartup = settingsStore.showOnStartup
        launchAtLogin = settingsStore.launchAtLogin
        spotifyClientID = settingsStore.spotifyClientID
        showPower = settingsStore.showPower
        showAudio = settingsStore.showAudio
        showCapture = settingsStore.showCapture
        showTimer = settingsStore.showTimer
        showNetwork = settingsStore.showNetwork
        showLiveSpectrum = settingsStore.showLiveSpectrum
        showCalendar = settingsStore.showCalendar

        bindSettings()
        bindServices()
        spectrumStatus
            .sink { [weak self] in self?.spectrumStatus = $0 }
            .store(in: &cancellables)

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

    /// Turning Calendar on asks for access first; if it is denied the switch stays off and a note is shown.
    func setCalendarEnabled(_ enabled: Bool) async {
        guard enabled else {
            applyCalendar(false)
            calendarAccessDenied = false
            return
        }

        let granted: Bool
        switch calendarAccess.authorizationStatus {
        case .authorized: granted = true
        case .denied: granted = false // the system will not prompt again
        case .notDetermined: granted = await calendarAccess.requestAccess()
        }
        applyCalendar(granted)
        calendarAccessDenied = !granted
    }

    /// Permission can be revoked or granted in System Settings while the app runs; call when
    /// Settings appears and when the app becomes active again.
    func refreshCalendarAccess() {
        calendarAccess.refreshAuthorizationStatus()
    }

    func openAudioCapturePrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture") else { return }
        openURL(url)
    }

    func openCalendarPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") else { return }
        openURL(url)
    }

    private func applyCalendar(_ value: Bool) {
        showCalendar = value
        settingsStore.showCalendar = value
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

        $showPower
            .dropFirst()
            .sink { [weak self] in self?.settingsStore.showPower = $0 }
            .store(in: &cancellables)

        $showAudio
            .dropFirst()
            .sink { [weak self] in self?.settingsStore.showAudio = $0 }
            .store(in: &cancellables)

        $showCapture
            .dropFirst()
            .sink { [weak self] in self?.settingsStore.showCapture = $0 }
            .store(in: &cancellables)

        $showTimer
            .dropFirst()
            .sink { [weak self] in self?.settingsStore.showTimer = $0 }
            .store(in: &cancellables)

        $showNetwork
            .dropFirst()
            .sink { [weak self] in self?.settingsStore.showNetwork = $0 }
            .store(in: &cancellables)

        $showLiveSpectrum
            .dropFirst()
            .sink { [weak self] in self?.settingsStore.showLiveSpectrum = $0 }
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

        // Access revoked in System Settings while Calendar is on: switch it off and explain.
        calendarAccess.authorizationStatusPublisher
            .sink { [weak self] status in
                guard let self, status == .denied, self.showCalendar else { return }
                self.applyCalendar(false)
                self.calendarAccessDenied = true
            }
            .store(in: &cancellables)

        notificationCenter.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshCalendarAccess() }
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

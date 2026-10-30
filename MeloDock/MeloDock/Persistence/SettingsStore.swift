import Combine
import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    @Published var preferredProvider: MusicProviderKind {
        didSet { defaults.set(preferredProvider.rawValue, forKey: Keys.preferredProvider) }
    }

    @Published var showOnStartup: Bool {
        didSet { defaults.set(showOnStartup, forKey: Keys.showOnStartup) }
    }

    @Published var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Keys.launchAtLogin) }
    }

    @Published var spotifyClientID: String {
        didSet { defaults.set(spotifyClientID, forKey: Keys.spotifyClientID) }
    }

    @Published var hotkey: HotkeyConfiguration {
        didSet {
            let data = try? JSONEncoder().encode(hotkey)
            defaults.set(data, forKey: Keys.hotkey)
        }
    }

    @Published var overlayVisible: Bool {
        didSet { defaults.set(overlayVisible, forKey: Keys.overlayVisible) }
    }

    @Published var showPower: Bool {
        didSet { defaults.set(showPower, forKey: Keys.showPower) }
    }

    @Published var showAudio: Bool {
        didSet { defaults.set(showAudio, forKey: Keys.showAudio) }
    }

    @Published var showCapture: Bool {
        didSet { defaults.set(showCapture, forKey: Keys.showCapture) }
    }

    @Published var showTimer: Bool {
        didSet { defaults.set(showTimer, forKey: Keys.showTimer) }
    }

    /// Only turned on after the user grants calendar access (see `SettingsViewModel.setCalendarEnabled`).
    @Published var showCalendar: Bool {
        didSet { defaults.set(showCalendar, forKey: Keys.showCalendar) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        preferredProvider = MusicProviderKind(rawValue: defaults.string(forKey: Keys.preferredProvider) ?? "") ?? .appleMusic
        showOnStartup = defaults.object(forKey: Keys.showOnStartup) as? Bool ?? true
        launchAtLogin = defaults.object(forKey: Keys.launchAtLogin) as? Bool ?? false
        spotifyClientID = defaults.string(forKey: Keys.spotifyClientID) ?? ""
        showPower = defaults.object(forKey: Keys.showPower) as? Bool ?? true
        showAudio = defaults.object(forKey: Keys.showAudio) as? Bool ?? true
        showCapture = defaults.object(forKey: Keys.showCapture) as? Bool ?? true
        showTimer = defaults.object(forKey: Keys.showTimer) as? Bool ?? true
        showCalendar = defaults.object(forKey: Keys.showCalendar) as? Bool ?? false
        overlayVisible = false // session-only: the island always starts collapsed

        if let data = defaults.data(forKey: Keys.hotkey),
           let decoded = try? JSONDecoder().decode(HotkeyConfiguration.self, from: data) {
            hotkey = decoded
        } else {
            hotkey = .default
        }
    }
}

private enum Keys {
    static let preferredProvider = "settings.preferredProvider"
    static let showOnStartup = "settings.showOnStartup"
    static let launchAtLogin = "settings.launchAtLogin"
    static let spotifyClientID = "settings.spotifyClientID"
    static let hotkey = "settings.hotkey"
    static let overlayVisible = "settings.overlayVisible"
    static let showPower = "settings.island.power"
    static let showAudio = "settings.island.audio"
    static let showCapture = "settings.island.capture"
    static let showTimer = "settings.island.timer"
    static let showCalendar = "settings.island.calendar"
}

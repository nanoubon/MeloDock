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

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        preferredProvider = MusicProviderKind(rawValue: defaults.string(forKey: Keys.preferredProvider) ?? "") ?? .appleMusic
        showOnStartup = defaults.object(forKey: Keys.showOnStartup) as? Bool ?? true
        launchAtLogin = defaults.object(forKey: Keys.launchAtLogin) as? Bool ?? false
        spotifyClientID = defaults.string(forKey: Keys.spotifyClientID) ?? ""
        overlayVisible = defaults.object(forKey: Keys.overlayVisible) as? Bool ?? false

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
}

import Combine
import Foundation

@MainActor
final class DIContainer: ObservableObject {
    static let shared = DIContainer()

    let settingsStore: SettingsStore
    let keychainService: KeychainService
    let permissionsService: PermissionsService
    let launchAtLoginService: LaunchAtLoginService
    let hotkeyService: HotkeyService
    let audioDeviceProvider: AudioDeviceProvider
    let appleMusicProvider: AppleMusicProvider
    let spotifyProvider: SpotifyProvider
    let proFeatureService: ProFeatureService

    lazy var islandViewModel: IslandViewModel = {
        IslandViewModel(
            settingsStore: settingsStore,
            musicProviders: musicProviders,
            audioDeviceProvider: audioDeviceProvider
        )
    }()

    lazy var islandCoordinator: IslandCoordinator = {
        let coordinator = IslandCoordinator(
            sources: [nowPlayingActivitySource],
            isIslandEnabled: settingsStore.showOnStartup
        )
        settingsStore.$showOnStartup
            .removeDuplicates()
            .assign(to: &coordinator.$isIslandEnabled)
        return coordinator
    }()

    lazy var settingsViewModel: SettingsViewModel = {
        SettingsViewModel(
            settingsStore: settingsStore,
            launchAtLoginService: launchAtLoginService,
            musicProviders: musicProviders,
            spotifyProvider: spotifyProvider,
            proFeatureService: proFeatureService
        )
    }()

    // Held here because the coordinator only keeps its subscription, not the source.
    private lazy var nowPlayingActivitySource = NowPlayingActivitySource(
        playbackStates: islandViewModel.$playbackState.eraseToAnyPublisher()
    )

    private lazy var musicProviders: [MusicProviderKind: MusicProvider] = [
        .appleMusic: appleMusicProvider,
        .spotify: spotifyProvider
    ]

    private init() {
        settingsStore = SettingsStore()
        keychainService = KeychainService()
        permissionsService = PermissionsService()
        launchAtLoginService = LaunchAtLoginService()
        hotkeyService = HotkeyService()
        audioDeviceProvider = CoreAudioService()

        appleMusicProvider = AppleMusicProvider()
        spotifyProvider = SpotifyProvider(
            settingsStore: settingsStore,
            keychainService: keychainService
        )

        proFeatureService = StoreKitProServiceStub()
    }
}

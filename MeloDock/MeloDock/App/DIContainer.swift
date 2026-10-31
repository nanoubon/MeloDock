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
        let viewModel = IslandViewModel(
            settingsStore: settingsStore,
            musicProviders: musicProviders,
            audioDeviceProvider: audioDeviceProvider
        )
        // Listens only while the Settings switch is on and music plays; it needs the view model's publishers,
        // so it is built here and handed back to the view model.
        let spectrum = CoreAudioTapSpectrumService(
            isEnabled: settingsStore.$showLiveSpectrum.eraseToAnyPublisher(),
            isPlaying: viewModel.$playbackState.map(\.isPlaying).eraseToAnyPublisher(),
            provider: viewModel.$selectedProvider.eraseToAnyPublisher()
        )
        viewModel.bindSpectrum(spectrum)
        spectrumSource = spectrum
        return viewModel
    }()

    // Held here and by the view model; Settings reads its status.
    private(set) var spectrumSource: SpectrumSource?

    lazy var islandCoordinator: IslandCoordinator = {
        let coordinator = IslandCoordinator(
            sources: [nowPlayingActivitySource, powerActivitySource, audioActivitySource, captureActivitySource,
                      timerActivitySource, calendarActivitySource, networkActivitySource],
            isIslandEnabled: settingsStore.showOnStartup
        )
        settingsStore.$showOnStartup
            .removeDuplicates()
            .assign(to: &coordinator.$isIslandEnabled)
        // Every kind except now playing can be switched off in Settings; the coordinator filters by kind.
        settingsStore.enabledKindsPublisher
            .assign(to: &coordinator.$enabledKinds)
        return coordinator
    }()

    lazy var settingsViewModel: SettingsViewModel = {
        _ = islandViewModel // builds the spectrum source
        return SettingsViewModel(
            settingsStore: settingsStore,
            launchAtLoginService: launchAtLoginService,
            musicProviders: musicProviders,
            spotifyProvider: spotifyProvider,
            proFeatureService: proFeatureService,
            calendarAccess: calendarService,
            spectrumStatus: spectrumSource?.statusPublisher ?? Just(.off).eraseToAnyPublisher()
        )
    }()

    // Constructing it does not prompt; access is only requested from the Settings Calendar switch.
    lazy var calendarService = CalendarService()

    // In-memory only. Held strongly here: the sources keep just subscriptions to it.
    lazy var timerModel = TimerModel()

    private lazy var timerActivitySource = TimerActivitySource(model: timerModel)

    // Held strongly like the timer model; it samples only while the Settings switch is on.
    lazy var networkSpeedModel = NetworkSpeedModel()

    private lazy var networkActivitySource = NetworkActivitySource(
        model: networkSpeedModel,
        isEnabled: settingsStore.$showNetwork.eraseToAnyPublisher()
    )

    // Inert until calendar access is granted from Settings; never prompts by itself.
    lazy var calendarActivitySource = CalendarActivitySource(provider: calendarService)

    // Held here because the coordinator only keeps its subscription, not the source.
    private lazy var nowPlayingActivitySource = NowPlayingActivitySource(
        playbackStates: islandViewModel.$playbackState.eraseToAnyPublisher()
    )

    // The services and sources below are held here because the coordinator only keeps its subscriptions.
    private lazy var powerSourceService = PowerSourceService()

    private lazy var powerActivitySource = PowerActivitySource(
        states: powerSourceService.statePublisher
    )

    private lazy var audioActivitySource: AudioActivitySource = {
        // The source only listens to the provider's publishers; IslandViewModel is what calls
        // `refresh()` on hardware events. Touching it here guarantees it exists (and has bound the
        // events) before the source subscribes, without a second refresh path.
        _ = islandViewModel
        return AudioActivitySource(provider: audioDeviceProvider)
    }()

    // Microphone only: camera detection stays off until the sandbox behaviour is verified on hardware.
    private lazy var captureActivityService = CaptureActivityService()

    private lazy var captureActivitySource = CaptureActivitySource(
        usage: captureActivityService.usagePublisher
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

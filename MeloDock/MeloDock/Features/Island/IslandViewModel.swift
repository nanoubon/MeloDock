import Combine
import Foundation

@MainActor
final class IslandViewModel: ObservableObject {
    @Published private(set) var playbackState: PlaybackState
    @Published private(set) var authState: ProviderAuthState = .unknown
    @Published private(set) var outputs: [AudioOutput] = []
    @Published var volume: Float = 0.5
    @Published var selectedOutputID: String = ""
    @Published var selectedProvider: MusicProviderKind

    private let settingsStore: SettingsStore
    private let musicProviders: [MusicProviderKind: MusicProvider]
    private let audioDeviceProvider: AudioDeviceProvider

    private var providerCancellables = Set<AnyCancellable>()
    private var cancellables = Set<AnyCancellable>()
    private var pollCancellable: AnyCancellable?

    init(
        settingsStore: SettingsStore,
        musicProviders: [MusicProviderKind: MusicProvider],
        audioDeviceProvider: AudioDeviceProvider
    ) {
        self.settingsStore = settingsStore
        self.musicProviders = musicProviders
        self.audioDeviceProvider = audioDeviceProvider

        let initialProvider = settingsStore.preferredProvider
        selectedProvider = initialProvider
        playbackState = PlaybackState.unavailable(provider: initialProvider, message: "No active playback")

        bindSettings()
        bindAudio()
        switchProvider(to: initialProvider)
        startPolling()
    }

    func bootstrap() async {
        await refresh()
    }

    var trackTitle: String {
        playbackState.track?.title ?? "Nothing Playing"
    }

    var trackArtist: String {
        playbackState.track?.artist ?? (playbackState.message ?? "Open Apple Music or Spotify")
    }

    var progressFraction: Double {
        playbackState.track?.progressFraction ?? 0
    }

    var artworkURL: URL? {
        playbackState.track?.artworkURL
    }

    func setProvider(_ provider: MusicProviderKind) {
        guard provider != selectedProvider else { return }
        selectedProvider = provider
        settingsStore.preferredProvider = provider
        switchProvider(to: provider)
        Task { await refresh() }
    }

    func authorizeCurrentProvider() {
        Task {
            await activeProvider?.authorize()
            await refresh()
        }
    }

    func togglePlayPause() {
        Task {
            await activeProvider?.togglePlayPause()
            await refresh()
        }
    }

    func playNext() {
        Task {
            await activeProvider?.playNext()
            await refresh()
        }
    }

    func playPrevious() {
        Task {
            await activeProvider?.playPrevious()
            await refresh()
        }
    }

    func setVolume(_ value: Float) {
        let clamped = max(0, min(1, value))
        volume = clamped
        audioDeviceProvider.setVolume(clamped)
    }

    func chooseOutput(_ id: String) {
        selectedOutputID = id
        audioDeviceProvider.setCurrentOutput(id: id)
    }

    private var activeProvider: MusicProvider? {
        musicProviders[selectedProvider]
    }

    private func bindSettings() {
        settingsStore.$preferredProvider
            .removeDuplicates()
            .sink { [weak self] provider in
                guard let self else { return }
                if self.selectedProvider != provider {
                    self.selectedProvider = provider
                    self.switchProvider(to: provider)
                }
            }
            .store(in: &cancellables)
    }

    private func bindAudio() {
        audioDeviceProvider.outputsPublisher
            .sink { [weak self] outputs in
                self?.outputs = outputs
                self?.selectedOutputID = outputs.first(where: { $0.isCurrent })?.id ?? ""
            }
            .store(in: &cancellables)

        audioDeviceProvider.volumePublisher
            .sink { [weak self] volume in
                self?.volume = volume
            }
            .store(in: &cancellables)
    }

    private func switchProvider(to provider: MusicProviderKind) {
        providerCancellables.removeAll()

        guard let providerInstance = musicProviders[provider] else { return }

        providerInstance.playbackStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.playbackState = state
            }
            .store(in: &providerCancellables)

        providerInstance.authStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.authState = state
            }
            .store(in: &providerCancellables)
    }

    private func startPolling() {
        pollCancellable = Timer.publish(every: 2.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { await self?.refresh() }
            }
    }

    private func refresh() async {
        await activeProvider?.refreshNowPlaying()
        await audioDeviceProvider.refresh()
    }
}

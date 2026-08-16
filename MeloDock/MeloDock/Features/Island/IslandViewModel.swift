import Combine
import Foundation

@MainActor
final class IslandViewModel: ObservableObject {
    @Published private(set) var playbackState: PlaybackState
    @Published private(set) var authState: ProviderAuthState = .unknown
    @Published private(set) var outputs: [AudioOutput] = []
    @Published private(set) var liveProgress: TimeInterval = 0
    @Published var volume: Float = 0.5
    @Published var selectedOutputID: String = ""
    @Published var selectedProvider: MusicProviderKind

    private let settingsStore: SettingsStore
    private let musicProviders: [MusicProviderKind: MusicProvider]
    private let audioDeviceProvider: AudioDeviceProvider

    private var providerCancellables = Set<AnyCancellable>()
    private var cancellables = Set<AnyCancellable>()
    private var pollCancellable: AnyCancellable?
    private var progressTickCancellable: AnyCancellable?
    private var isRefreshing = false
    private var pendingRefresh = false
    private var pendingForceAudioRefresh = false
    private var hiddenTickCounter = 0
    private var lastAudioRefreshAt = Date.distantPast
    private var lastProgressTickAt = Date()

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
        if settingsStore.overlayVisible {
            startProgressTicker()
        }
    }

    func bootstrap() async {
        await refresh(forceAudioRefresh: true)
    }

    var trackTitle: String {
        if let title = displayMetadata(playbackState.track?.title), title.isEmpty == false {
            return title
        }
        return playbackState.isPlaying ? "Now Playing" : "Nothing Playing"
    }

    var trackArtist: String {
        if let artist = displayMetadata(playbackState.track?.artist), artist.isEmpty == false {
            return artist
        }
        return playbackState.message ?? "Open Apple Music or Spotify"
    }

    var progressFraction: Double {
        if let duration = playbackState.track?.duration, duration > 0 {
            return min(max(liveProgress / duration, 0), 1)
        }
        guard playbackState.isPlaying else { return 0 }
        let cycle = liveProgress.truncatingRemainder(dividingBy: 20)
        return cycle / 20
    }

    var artworkURL: URL? {
        playbackState.track?.artworkURL
    }

    var shouldShowSpectrum: Bool {
        playbackState.isPlaying || playbackState.track != nil
    }

    var spectrumProgress: TimeInterval {
        liveProgress
    }

    var spectrumTempoBPM: Double {
        if let tempo = playbackState.track?.tempoBPM, tempo > 0 {
            return tempo
        }
        return 120
    }

    var elapsedTimeText: String {
        formatTime(liveProgress)
    }

    var durationTimeText: String {
        guard let duration = playbackState.track?.duration, duration > 0 else { return "--:--" }
        return formatTime(duration)
    }

    var spectrumSeed: Int {
        guard let id = playbackState.track?.id else { return 17 }
        return id.unicodeScalars.reduce(17) { partialResult, scalar in
            (partialResult &* 31) &+ Int(scalar.value)
        }
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
                    Task { await self.refresh() }
                }
            }
            .store(in: &cancellables)

        settingsStore.$overlayVisible
            .removeDuplicates()
            .sink { [weak self] isVisible in
                guard let self else { return }
                if isVisible {
                    self.lastProgressTickAt = Date()
                    self.startProgressTicker()
                    Task { await self.refresh(forceAudioRefresh: true) }
                } else {
                    self.progressTickCancellable = nil
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
                guard let self else { return }
                if abs(self.volume - volume) > 0.01 {
                    self.volume = volume
                }
            }
            .store(in: &cancellables)
    }

    private func switchProvider(to provider: MusicProviderKind) {
        providerCancellables.removeAll()

        guard let providerInstance = musicProviders[provider] else { return }

        providerInstance.playbackStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.handlePlaybackStateUpdate(state)
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
                guard let self else { return }

                if self.settingsStore.overlayVisible == false {
                    self.hiddenTickCounter += 1
                    if self.hiddenTickCounter % 3 != 0 {
                        return
                    }
                } else {
                    self.hiddenTickCounter = 0
                }

                Task { await self.refresh() }
            }
    }

    private func startProgressTicker() {
        progressTickCancellable = Timer.publish(every: 1.0 / 15.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.advanceLiveProgress()
            }
    }

    private func handlePlaybackStateUpdate(_ state: PlaybackState) {
        var normalizedState = state
        if normalizedState.track == nil,
           (normalizedState.status == .playing || normalizedState.status == .paused),
           let previousTrack = playbackState.track {
            normalizedState.track = previousTrack
        }

        let previousTrackID = playbackState.track?.id
        let previousProgress = liveProgress
        playbackState = normalizedState

        if let track = normalizedState.track {
            liveProgress = PlaybackProgress.resolved(
                previousTrackID: previousTrackID,
                previousProgress: previousProgress,
                track: track,
                isPlaying: normalizedState.isPlaying
            )
        } else {
            liveProgress = 0
        }

        lastProgressTickAt = Date()
    }

    private func advanceLiveProgress() {
        guard playbackState.isPlaying else {
            lastProgressTickAt = Date()
            return
        }

        let now = Date()
        let delta = now.timeIntervalSince(lastProgressTickAt)
        guard delta > 0 else { return }

        if let duration = playbackState.track?.duration, duration > 0 {
            liveProgress = min(duration, liveProgress + delta)
        } else {
            liveProgress += delta
        }
        lastProgressTickAt = now
    }

    private func refresh(forceAudioRefresh: Bool = false) async {
        if isRefreshing {
            pendingRefresh = true
            pendingForceAudioRefresh = pendingForceAudioRefresh || forceAudioRefresh
            return
        }

        isRefreshing = true
        var forceAudio = forceAudioRefresh
        defer { isRefreshing = false }

        repeat {
            pendingRefresh = false
            let forceThisPass = forceAudio || pendingForceAudioRefresh
            forceAudio = false
            pendingForceAudioRefresh = false

            await activeProvider?.refreshNowPlaying()

            let now = Date()
            let shouldRefreshAudio = forceThisPass || now.timeIntervalSince(lastAudioRefreshAt) >= 8.0
            if shouldRefreshAudio {
                await audioDeviceProvider.refresh()
                lastAudioRefreshAt = now
            }
        } while pendingRefresh
    }

    private func displayMetadata(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }

        let normalized = trimmed.lowercased()
        if normalized == "missing value"
            || normalized == "missingvalue"
            || normalized == "(null)"
            || normalized == "<null>"
            || normalized == "nil" {
            return nil
        }

        return trimmed
    }

    private func formatTime(_ value: TimeInterval) -> String {
        let totalSeconds = max(0, Int(value.rounded(.down)))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

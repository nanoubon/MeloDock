import Combine
import Foundation
import MusicKit

@MainActor
final class AppleMusicProvider: MusicProvider {
    let kind: MusicProviderKind = .appleMusic

    private let player = ApplicationMusicPlayer.shared
    private let playbackSubject = CurrentValueSubject<PlaybackState, Never>(
        .unavailable(provider: .appleMusic, message: "Authorize Apple Music in Settings.")
    )
    private let authSubject = CurrentValueSubject<ProviderAuthState, Never>(.unknown)

    var authState: ProviderAuthState { authSubject.value }
    var authStatePublisher: AnyPublisher<ProviderAuthState, Never> { authSubject.eraseToAnyPublisher() }
    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> { playbackSubject.eraseToAnyPublisher() }

    init() {
        updateAuthState(with: MusicAuthorization.currentStatus)
    }

    func authorize() async {
        let status = await MusicAuthorization.request()
        updateAuthState(with: status)
    }

    func refreshNowPlaying() async {
        updateAuthState(with: MusicAuthorization.currentStatus)

        guard authSubject.value == .authorized else {
            playbackSubject.send(.unavailable(
                provider: .appleMusic,
                message: "Apple Music access is not authorized."
            ))
            return
        }

        let track = mapCurrentTrack()
        let status = mapPlaybackStatus(player.state.playbackStatus)

        var state = PlaybackState(provider: .appleMusic, status: status, track: track, message: nil)
        if track == nil {
            state.message = "No Apple Music track is active."
        }

        playbackSubject.send(state)
    }

    func togglePlayPause() async {
        guard authSubject.value == .authorized else { return }

        do {
            if player.state.playbackStatus == .playing {
                player.pause()
            } else {
                try await player.play()
            }
        } catch {
            playbackSubject.send(.unavailable(provider: .appleMusic, message: error.localizedDescription))
        }

        await refreshNowPlaying()
    }

    func playNext() async {
        guard authSubject.value == .authorized else { return }

        do {
            try await player.skipToNextEntry()
        } catch {
            playbackSubject.send(.unavailable(provider: .appleMusic, message: error.localizedDescription))
        }

        await refreshNowPlaying()
    }

    func playPrevious() async {
        guard authSubject.value == .authorized else { return }

        do {
            try await player.skipToPreviousEntry()
        } catch {
            playbackSubject.send(.unavailable(provider: .appleMusic, message: error.localizedDescription))
        }

        await refreshNowPlaying()
    }

    private func updateAuthState(with status: MusicAuthorization.Status) {
        switch status {
        case .authorized:
            authSubject.send(.authorized)
        case .denied, .restricted:
            authSubject.send(.unauthorized)
        case .notDetermined:
            authSubject.send(.unknown)
        @unknown default:
            authSubject.send(.unavailable("Apple Music authorization status is unavailable."))
        }
    }

    private func mapPlaybackStatus(_ status: MusicPlayer.PlaybackStatus) -> PlaybackStatus {
        switch status {
        case .playing:
            return .playing
        case .paused:
            return .paused
        case .stopped:
            return .stopped
        default:
            return .paused
        }
    }

    private func mapCurrentTrack() -> Track? {
        guard let song = player.queue.currentEntry?.item as? Song else { return nil }

        let duration = song.duration ?? 0
        let progress = max(0, player.playbackTime)
        let artworkURL = song.artwork?.url(width: 240, height: 240)

        return Track(
            id: song.id.rawValue,
            title: song.title,
            artist: song.artistName,
            artworkURL: artworkURL,
            duration: duration,
            progress: progress
        )
    }
}

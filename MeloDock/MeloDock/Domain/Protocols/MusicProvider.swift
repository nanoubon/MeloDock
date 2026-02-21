import Combine
import Foundation

@MainActor
protocol MusicProvider: AnyObject {
    var kind: MusicProviderKind { get }
    var authState: ProviderAuthState { get }
    var authStatePublisher: AnyPublisher<ProviderAuthState, Never> { get }
    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> { get }

    func authorize() async
    func refreshNowPlaying() async
    func togglePlayPause() async
    func playNext() async
    func playPrevious() async
}

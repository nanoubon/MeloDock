import Combine

enum SpectrumStatus: Equatable {
    /// Switched off in Settings, or nothing is playing.
    case off
    /// Listening, but no sound has arrived yet.
    case waiting
    /// Real levels are flowing.
    case live
    /// The system delivered only silence while music played: the audio permission is most likely missing.
    case denied
    /// macOS older than 14.2 has no process taps.
    case unsupported
}

/// Real audio levels for the island's spectrum. Without levels the view falls back to its synthetic animation.
@MainActor
protocol SpectrumSource: AnyObject {
    /// One 0...1 level per frequency band, or nil when there is no real data.
    var levelsPublisher: AnyPublisher<[Float]?, Never> { get }
    var statusPublisher: AnyPublisher<SpectrumStatus, Never> { get }
}

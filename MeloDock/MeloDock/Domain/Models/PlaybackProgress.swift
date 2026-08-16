import Foundation

enum PlaybackProgress {
    /// How far behind a provider snapshot can be before we treat it as a real seek.
    static let staleTolerance: TimeInterval = 1.5

    /// Resolves displayed progress from a new provider snapshot.
    ///
    /// Providers often report slightly stale positions while a local ticker is
    /// already ahead. Those should not jump backward. A user seek, however,
    /// can jump backward by more than `staleTolerance` and must be honored.
    static func resolved(
        previousTrackID: String?,
        previousProgress: TimeInterval,
        track: Track,
        isPlaying: Bool,
        staleTolerance: TimeInterval = staleTolerance
    ) -> TimeInterval {
        if isPlaying, previousTrackID == track.id {
            if track.progress + staleTolerance < previousProgress {
                return track.progress
            }
            return max(previousProgress, track.progress)
        }
        return track.progress
    }
}

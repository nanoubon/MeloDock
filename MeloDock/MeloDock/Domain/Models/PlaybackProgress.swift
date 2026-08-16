import Foundation

enum PlaybackProgress {
    /// How far a new provider snapshot can sit behind the previous snapshot
    /// before we treat it as a real seek. Compared to snapshots, not the local ticker.
    static let staleTolerance: TimeInterval = 1.5

    /// Resolves displayed progress from a new provider snapshot.
    ///
    /// The local ticker often runs ahead of the last provider report. Those stale
    /// reports must not jump the bar backward. A user seek is detected when the
    /// snapshot itself moves backward versus the previous snapshot.
    static func resolved(
        previousTrackID: String?,
        previousLiveProgress: TimeInterval,
        previousSnapshotProgress: TimeInterval?,
        track: Track,
        isPlaying: Bool,
        staleTolerance: TimeInterval = staleTolerance
    ) -> TimeInterval {
        guard previousTrackID == track.id else {
            return track.progress
        }

        if let previousSnapshot = previousSnapshotProgress,
           track.progress + staleTolerance < previousSnapshot {
            return track.progress
        }

        if isPlaying {
            return max(previousLiveProgress, track.progress)
        }

        return track.progress
    }
}

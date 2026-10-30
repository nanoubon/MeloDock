import Foundation

/// Pure progress rules for the island. A track without a known duration (duration <= 0, e.g. streamed
/// Apple Music tracks) has no meaningful progress, so the fraction is 0 and the UI hides the rail.
enum PlaybackProgress {
    static func isKnown(duration: TimeInterval?) -> Bool {
        guard let duration, duration.isFinite else { return false }
        return duration > 0
    }

    static func fraction(progress: TimeInterval, duration: TimeInterval?) -> Double {
        guard isKnown(duration: duration), let duration else { return 0 }
        return min(max(progress / duration, 0), 1)
    }
}

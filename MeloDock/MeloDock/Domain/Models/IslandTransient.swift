import Foundation

/// A short-lived notice shown over the island (charging, volume change, ...).
struct IslandTransient: Identifiable, Equatable {
    enum Payload: Equatable {
        case charging(percent: Int, isCharging: Bool)
        case batteryLow(percent: Int)
        case bluetooth(name: String, connected: Bool)
        case volume(Float)
        case output(name: String)
        case timerDone
    }

    /// Items with the same id coalesce (a newer one replaces an older one).
    let id: String
    let kind: IslandActivity.Kind
    let payload: Payload
    let duration: TimeInterval
    /// Sticky items stay until the queue is touched/cleared or replaced instead of expiring on their own clock.
    let sticky: Bool
}

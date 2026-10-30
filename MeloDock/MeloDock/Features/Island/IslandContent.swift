/// Chooses what the collapsed island's ears show for the primary activity.
enum CompactContent: Equatable {
    case nowPlaying
    case capture(mic: Bool, camera: Bool)
    /// Timer ears read the `TimerModel`; the activity carries no payload.
    case timer
    /// Calendar ears read `CalendarActivitySource.activeEvent`.
    case calendar
    /// No primary activity (or a kind without ears): the ears stay empty.
    case empty

    static func make(for primary: IslandActivity?) -> CompactContent {
        guard let primary else { return .empty }
        switch (primary.kind, primary.detail) {
        case (.nowPlaying, _): return .nowPlaying
        case let (.capture, .capture(mic, camera)): return .capture(mic: mic, camera: camera)
        case (.timer, _): return .timer
        case (.calendar, _): return .calendar
        default: return .empty
        }
    }
}

/// Pure rules for the expanded island's tab strip and which page it shows.
enum IslandTab {
    /// Display order. Now playing is the always-present "home" page and the timer is always reachable,
    /// so the strip only changes when a calendar event appears or ends (at the trailing end).
    private static let order: [IslandActivity.Kind] = [.nowPlaying, .timer, .calendar]

    /// Tabs for the active activities. Kinds without a page (power, audio, capture) never get a tab.
    static func tabs(from activities: [IslandActivity], timerEnabled: Bool = true) -> [IslandActivity.Kind] {
        let present = Set(activities.map(\.kind))
        return order.filter { kind in
            switch kind {
            case .nowPlaying: true
            case .timer: timerEnabled
            case .calendar: present.contains(.calendar)
            default: false
            }
        }
    }

    /// The page to show. An explicit pick wins while its tab still exists; otherwise the primary activity's page
    /// (then the secondary's), falling back to now playing.
    static func page(selection: IslandSelection, tabs: [IslandActivity.Kind],
                     requested: IslandActivity.Kind?) -> IslandActivity.Kind {
        if let requested, tabs.contains(requested) { return requested }
        for activity in [selection.primary, selection.secondary] {
            if let kind = activity?.kind, tabs.contains(kind) { return kind }
        }
        return .nowPlaying
    }
}

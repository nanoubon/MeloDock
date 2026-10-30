/// One thing the island can show (now playing, timer, ...).
struct IslandActivity: Identifiable, Equatable {
    enum Kind: Hashable, CaseIterable { case nowPlaying, power, audio, capture, timer, calendar }

    enum Priority {
        static let timer = 100
        static let calendar = 80
        static let nowPlayingPlaying = 60
        static let capture = 40
        static let nowPlayingPaused = 20
    }

    /// Kind-specific data. Timer and calendar carry no payload until Phase 3 defines it.
    enum Detail: Equatable {
        case nowPlaying
        case capture(mic: Bool, camera: Bool)
        case timer
        case calendar
    }

    let id: String
    let kind: Kind
    let priority: Int
    let detail: Detail

    init(id: String, kind: Kind, priority: Int, detail: Detail = .nowPlaying) {
        self.id = id
        self.kind = kind
        self.priority = priority
        self.detail = detail
    }
}

/// The top two activities by priority.
struct IslandSelection: Equatable {
    var primary: IslandActivity?
    var secondary: IslandActivity?

    /// Priority descending; ties broken by id ascending.
    static func select(from activities: [IslandActivity]) -> IslandSelection {
        let sorted = activities.sorted {
            $0.priority != $1.priority ? $0.priority > $1.priority : $0.id < $1.id
        }
        return IslandSelection(primary: sorted.first, secondary: sorted.dropFirst().first)
    }
}

/// Which activity kinds the user has switched on. Now playing has no switch and is always enabled.
enum IslandKindFilter {
    static func enabledKinds(showPower: Bool, showAudio: Bool, showCapture: Bool,
                             showTimer: Bool, showCalendar: Bool) -> Set<IslandActivity.Kind> {
        var kinds = Set(IslandActivity.Kind.allCases)
        if !showPower { kinds.remove(.power) }
        if !showAudio { kinds.remove(.audio) }
        if !showCapture { kinds.remove(.capture) }
        if !showTimer { kinds.remove(.timer) }
        if !showCalendar { kinds.remove(.calendar) }
        return kinds
    }

    static let all = Set(IslandActivity.Kind.allCases)
}

/// One thing the island can show (now playing, timer, ...).
struct IslandActivity: Identifiable, Equatable {
    enum Kind: Hashable, CaseIterable { case nowPlaying, power, audio, capture, timer, calendar, network }

    enum Priority {
        static let timer = 100
        static let calendar = 80
        static let nowPlayingPlaying = 60
        static let capture = 40
        static let nowPlayingPaused = 20
        /// Lowest: every other activity takes the ears from the network speed.
        static let network = 10
    }

    /// Kind-specific data. Timer, calendar and network carry no payload: their views read their own models.
    enum Detail: Equatable {
        case nowPlaying
        case capture(mic: Bool, camera: Bool)
        case timer
        case calendar
        case network
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

    /// Priority descending; ties broken by id ascending. The network speed can be primary but never gets the
    /// secondary circle: it is an always-on ambient readout, not a second thing to look at.
    static func select(from activities: [IslandActivity]) -> IslandSelection {
        let sorted = activities.sorted {
            $0.priority != $1.priority ? $0.priority > $1.priority : $0.id < $1.id
        }
        return IslandSelection(primary: sorted.first,
                               secondary: sorted.dropFirst().first { $0.kind != .network })
    }
}

/// Which activity kinds the user has switched on. Now playing has no switch and is always enabled.
enum IslandKindFilter {
    static func enabledKinds(showPower: Bool, showAudio: Bool, showCapture: Bool,
                             showTimer: Bool, showCalendar: Bool,
                             showNetwork: Bool = true) -> Set<IslandActivity.Kind> {
        var kinds = Set(IslandActivity.Kind.allCases)
        if !showPower { kinds.remove(.power) }
        if !showAudio { kinds.remove(.audio) }
        if !showCapture { kinds.remove(.capture) }
        if !showTimer { kinds.remove(.timer) }
        if !showCalendar { kinds.remove(.calendar) }
        if !showNetwork { kinds.remove(.network) }
        return kinds
    }

    static let all = Set(IslandActivity.Kind.allCases)
}

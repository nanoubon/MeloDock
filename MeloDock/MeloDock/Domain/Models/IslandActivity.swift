import Combine

/// One thing the island can show (now playing, timer, ...).
struct IslandActivity: Identifiable, Equatable {
    enum Kind: Hashable { case nowPlaying, power, audio, capture, timer, calendar }

    enum Priority {
        static let timer = 100
        static let calendar = 80
        static let nowPlayingPlaying = 60
        static let capture = 40
        static let nowPlayingPaused = 20
    }

    let id: String
    let kind: Kind
    let priority: Int
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

@MainActor
protocol ActivitySource: AnyObject {
    var activitiesPublisher: AnyPublisher<[IslandActivity], Never> { get }
}

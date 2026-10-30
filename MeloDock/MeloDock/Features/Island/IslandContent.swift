/// Chooses what the collapsed island's ears show for the primary activity.
enum CompactContent: Equatable {
    case nowPlaying
    case capture(mic: Bool, camera: Bool)
    /// A primary kind with no compact view yet (timer, calendar): the ears stay empty.
    case empty

    static func make(for primary: IslandActivity?) -> CompactContent {
        guard let primary else { return .empty }
        switch (primary.kind, primary.detail) {
        case (.nowPlaying, _): return .nowPlaying
        case let (.capture, .capture(mic, camera)): return .capture(mic: mic, camera: camera)
        default: return .empty
        }
    }
}

import Foundation

struct Track: Identifiable, Equatable, Codable {
    let id: String
    let title: String
    let artist: String
    let artworkURL: URL?
    let duration: TimeInterval
    var progress: TimeInterval

    init(
        id: String,
        title: String,
        artist: String,
        artworkURL: URL?,
        duration: TimeInterval,
        progress: TimeInterval
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.artworkURL = artworkURL
        self.duration = max(0, duration)
        self.progress = max(0, min(progress, max(0, duration)))
    }

    var progressFraction: Double {
        guard duration > 0 else { return 0 }
        return min(max(progress / duration, 0), 1)
    }
}

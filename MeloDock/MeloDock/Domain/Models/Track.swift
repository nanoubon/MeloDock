import Foundation

struct Track: Identifiable, Equatable, Codable {
    let id: String
    let title: String
    let artist: String
    let artworkURL: URL?
    let tempoBPM: Double?
    let duration: TimeInterval
    var progress: TimeInterval

    init(
        id: String,
        title: String,
        artist: String,
        artworkURL: URL?,
        tempoBPM: Double? = nil,
        duration: TimeInterval,
        progress: TimeInterval
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.artworkURL = artworkURL
        if let tempoBPM, tempoBPM > 0 {
            self.tempoBPM = min(tempoBPM, 260)
        } else {
            self.tempoBPM = nil
        }
        self.duration = max(0, duration)
        if self.duration > 0 {
            self.progress = max(0, min(progress, self.duration))
        } else {
            self.progress = max(0, progress)
        }
    }

    var progressFraction: Double {
        guard duration > 0 else { return 0 }
        return min(max(progress / duration, 0), 1)
    }
}

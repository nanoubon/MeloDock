#if canImport(XCTest)
import XCTest
@testable import MeloDock

final class PlaybackProgressTests: XCTestCase {
    func testKeepsLocalProgressWhenProviderIsSlightlyStale() {
        let track = Track(
            id: "song-1",
            title: "Song",
            artist: "Artist",
            artworkURL: nil,
            duration: 200,
            progress: 40
        )

        let resolved = PlaybackProgress.resolved(
            previousTrackID: "song-1",
            previousProgress: 41.2,
            track: track,
            isPlaying: true
        )

        XCTAssertEqual(resolved, 41.2, accuracy: 0.0001)
    }

    func testHonorsBackwardSeekBeyondStaleTolerance() {
        let track = Track(
            id: "song-1",
            title: "Song",
            artist: "Artist",
            artworkURL: nil,
            duration: 200,
            progress: 20
        )

        let resolved = PlaybackProgress.resolved(
            previousTrackID: "song-1",
            previousProgress: 90,
            track: track,
            isPlaying: true
        )

        XCTAssertEqual(resolved, 20, accuracy: 0.0001)
    }

    func testResetsProgressWhenTrackChanges() {
        let track = Track(
            id: "song-2",
            title: "Next",
            artist: "Artist",
            artworkURL: nil,
            duration: 180,
            progress: 3
        )

        let resolved = PlaybackProgress.resolved(
            previousTrackID: "song-1",
            previousProgress: 90,
            track: track,
            isPlaying: true
        )

        XCTAssertEqual(resolved, 3, accuracy: 0.0001)
    }
}
#endif

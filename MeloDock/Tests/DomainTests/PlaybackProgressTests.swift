#if canImport(XCTest)
import XCTest
@testable import MeloDock

final class PlaybackProgressTests: XCTestCase {
    func testKeepsLocalProgressWhenProviderSnapshotIsUnchanged() {
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
            previousLiveProgress: 42.4,
            previousSnapshotProgress: 40,
            track: track,
            isPlaying: true
        )

        XCTAssertEqual(resolved, 42.4, accuracy: 0.0001)
    }

    func testKeepsLocalProgressWhenPollSnapshotIsTwoSecondsBehindLive() {
        let track = Track(
            id: "song-1",
            title: "Song",
            artist: "Artist",
            artworkURL: nil,
            duration: 200,
            progress: 40.2
        )

        let resolved = PlaybackProgress.resolved(
            previousTrackID: "song-1",
            previousLiveProgress: 42.2,
            previousSnapshotProgress: 40,
            track: track,
            isPlaying: true
        )

        XCTAssertEqual(resolved, 42.2, accuracy: 0.0001)
    }

    func testHonorsBackwardSeekWhenSnapshotItselfJumpsBack() {
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
            previousLiveProgress: 91,
            previousSnapshotProgress: 90,
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
            previousLiveProgress: 90,
            previousSnapshotProgress: 88,
            track: track,
            isPlaying: true
        )

        XCTAssertEqual(resolved, 3, accuracy: 0.0001)
    }

    func testPausedSeekUsesSnapshotProgress() {
        let track = Track(
            id: "song-1",
            title: "Song",
            artist: "Artist",
            artworkURL: nil,
            duration: 200,
            progress: 15
        )

        let resolved = PlaybackProgress.resolved(
            previousTrackID: "song-1",
            previousLiveProgress: 90,
            previousSnapshotProgress: 90,
            track: track,
            isPlaying: false
        )

        XCTAssertEqual(resolved, 15, accuracy: 0.0001)
    }
}
#endif

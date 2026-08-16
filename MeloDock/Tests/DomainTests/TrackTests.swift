#if canImport(XCTest)
import XCTest
@testable import MeloDock

final class TrackTests: XCTestCase {
    func testProgressFractionClampsToOne() {
        let track = Track(
            id: "1",
            title: "Song",
            artist: "Artist",
            artworkURL: nil,
            duration: 100,
            progress: 180
        )

        XCTAssertEqual(track.progressFraction, 1.0, accuracy: 0.0001)
    }

    func testProgressFractionForZeroDurationIsZero() {
        let track = Track(
            id: "1",
            title: "Song",
            artist: "Artist",
            artworkURL: nil,
            duration: 0,
            progress: 0
        )

        XCTAssertEqual(track.progressFraction, 0.0, accuracy: 0.0001)
    }

    func testZeroDurationPreservesLiveProgress() {
        let track = Track(
            id: "radio",
            title: "Live Stream",
            artist: "Station",
            artworkURL: nil,
            duration: 0,
            progress: 42
        )

        XCTAssertEqual(track.progress, 42, accuracy: 0.0001)
        XCTAssertEqual(track.progressFraction, 0.0, accuracy: 0.0001)
    }
}
#endif

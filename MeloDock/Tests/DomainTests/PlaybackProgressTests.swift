#if canImport(XCTest)
import XCTest
@testable import MeloDock

final class PlaybackProgressTests: XCTestCase {
    func testUnknownDurationHasNoProgressEvenWhileAdvancing() {
        XCTAssertFalse(PlaybackProgress.isKnown(duration: 0))
        XCTAssertFalse(PlaybackProgress.isKnown(duration: nil))
        XCTAssertFalse(PlaybackProgress.isKnown(duration: -5))
        XCTAssertEqual(PlaybackProgress.fraction(progress: 0, duration: 0), 0)
        XCTAssertEqual(PlaybackProgress.fraction(progress: 37, duration: 0), 0)
        XCTAssertEqual(PlaybackProgress.fraction(progress: 37, duration: nil), 0)
    }

    func testKnownDurationComputesClampedFraction() {
        XCTAssertTrue(PlaybackProgress.isKnown(duration: 200))
        XCTAssertEqual(PlaybackProgress.fraction(progress: 50, duration: 200), 0.25)
        XCTAssertEqual(PlaybackProgress.fraction(progress: 500, duration: 200), 1)
        XCTAssertEqual(PlaybackProgress.fraction(progress: -3, duration: 200), 0)
    }
}
#endif

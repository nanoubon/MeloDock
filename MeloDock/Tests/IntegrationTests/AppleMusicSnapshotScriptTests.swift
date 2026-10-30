#if canImport(XCTest)
import XCTest
@testable import MeloDock

final class AppleMusicSnapshotScriptTests: XCTestCase {
    /// The sandbox rejects a script that stores `current track` in a variable (-10004), which
    /// silently dropped duration/BPM/track ID. Every statement must reference `current track` directly.
    func testSnapshotScriptNeverBindsCurrentTrackToVariable() {
        let script = AppleMusicProvider.snapshotScript
        XCTAssertFalse(script.contains("to current track"), "variable bound to current track")
        XCTAssertFalse(script.contains(" of t "), "reference through a track variable")
        XCTAssertFalse(script.contains(" of t)"), "reference through a track variable")
        XCTAssertTrue(script.contains("database ID of current track"))
    }
}
#endif

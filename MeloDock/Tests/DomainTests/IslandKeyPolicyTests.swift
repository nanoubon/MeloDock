#if canImport(XCTest)
import XCTest
@testable import MeloDock

final class IslandKeyPolicyTests: XCTestCase {
    func testOnlyTheExpandedTimerPageMayBecomeKey() {
        XCTAssertTrue(IslandKeyPolicy.canBecomeKey(isExpanded: true, page: .timer))
        XCTAssertFalse(IslandKeyPolicy.canBecomeKey(isExpanded: false, page: .timer))
        XCTAssertFalse(IslandKeyPolicy.canBecomeKey(isExpanded: true, page: .calendar))
        XCTAssertFalse(IslandKeyPolicy.canBecomeKey(isExpanded: true, page: .nowPlaying))
    }
}
#endif

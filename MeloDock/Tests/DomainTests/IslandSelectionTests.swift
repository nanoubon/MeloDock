#if canImport(XCTest)
import XCTest
@testable import MeloDock

final class IslandSelectionTests: XCTestCase {
    private func activity(_ id: String, _ kind: IslandActivity.Kind, _ priority: Int) -> IslandActivity {
        IslandActivity(id: id, kind: kind, priority: priority)
    }

    func testEmptyYieldsNoPrimaryOrSecondary() {
        let s = IslandSelection.select(from: [])
        XCTAssertNil(s.primary)
        XCTAssertNil(s.secondary)
    }

    func testOrdersByPriorityDescending() {
        let timer = activity("timer", .timer, IslandActivity.Priority.timer)
        let playing = activity("np", .nowPlaying, IslandActivity.Priority.nowPlayingPlaying)
        let capture = activity("cap", .capture, IslandActivity.Priority.capture)
        let s = IslandSelection.select(from: [capture, playing, timer])
        XCTAssertEqual(s.primary, timer)
        XCTAssertEqual(s.secondary, playing)
    }

    func testTieBrokenByIdAscending() {
        let a = activity("a", .audio, 50)
        let b = activity("b", .power, 50)
        let s = IslandSelection.select(from: [b, a])
        XCTAssertEqual(s.primary, a)
        XCTAssertEqual(s.secondary, b)
    }

    func testSingleActivityHasNoSecondary() {
        let a = activity("a", .audio, 50)
        let s = IslandSelection.select(from: [a])
        XCTAssertEqual(s.primary, a)
        XCTAssertNil(s.secondary)
    }
}
#endif

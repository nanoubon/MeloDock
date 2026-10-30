#if canImport(XCTest)
import XCTest
@testable import MeloDock

final class IslandTabTests: XCTestCase {
    private func act(_ kind: IslandActivity.Kind, _ priority: Int) -> IslandActivity {
        IslandActivity(id: "\(kind)", kind: kind, priority: priority)
    }

    private func selection(_ list: [IslandActivity]) -> IslandSelection { IslandSelection.select(from: list) }

    func testTabsAlwaysIncludeHomeAndTimer() {
        XCTAssertEqual(IslandTab.tabs(from: []), [.nowPlaying, .timer])
    }

    func testTabsAddCalendarWhenActiveInFixedOrder() {
        let list = [act(.calendar, 80), act(.timer, 100), act(.nowPlaying, 60)]
        XCTAssertEqual(IslandTab.tabs(from: list), [.nowPlaying, .timer, .calendar])
    }

    func testKindsWithoutPagesAreIgnored() {
        XCTAssertEqual(IslandTab.tabs(from: [act(.power, 5), act(.audio, 5), act(.capture, 40)]), [.nowPlaying, .timer])
    }

    func testTimerTabCanBeDisabled() {
        XCTAssertEqual(IslandTab.tabs(from: [], timerEnabled: false), [.nowPlaying])
    }

    func testDefaultPageIsPrimaryKind() {
        let list = [act(.timer, 100), act(.nowPlaying, 60)]
        XCTAssertEqual(IslandTab.page(selection: selection(list), tabs: IslandTab.tabs(from: list), requested: nil), .timer)
    }

    func testDefaultFallsBackToHomeWhenNothingActive() {
        XCTAssertEqual(IslandTab.page(selection: selection([]), tabs: IslandTab.tabs(from: []), requested: nil), .nowPlaying)
    }

    func testPrimaryWithoutPageFallsToSecondaryThenHome() {
        let list = [act(.capture, 40), act(.calendar, 30)]
        XCTAssertEqual(IslandTab.page(selection: selection(list), tabs: IslandTab.tabs(from: list), requested: nil), .calendar)
        let only = [act(.capture, 40)]
        XCTAssertEqual(IslandTab.page(selection: selection(only), tabs: IslandTab.tabs(from: only), requested: nil), .nowPlaying)
    }

    func testRequestedPickSticks() {
        let list = [act(.timer, 100), act(.nowPlaying, 60)]
        XCTAssertEqual(IslandTab.page(selection: selection(list), tabs: IslandTab.tabs(from: list), requested: .nowPlaying), .nowPlaying)
    }

    func testRequestedTimerReachableWithoutActiveTimer() {
        let list = [act(.nowPlaying, 60)]
        XCTAssertEqual(IslandTab.page(selection: selection(list), tabs: IslandTab.tabs(from: list), requested: .timer), .timer)
    }

    func testRequestedCalendarDropsWhenEventEnds() {
        let list = [act(.nowPlaying, 60)]
        XCTAssertEqual(IslandTab.page(selection: selection(list), tabs: IslandTab.tabs(from: list), requested: .calendar), .nowPlaying)
    }
}
#endif

import Combine
import XCTest
@testable import MeloDock

@MainActor
private final class FakeSource: ActivitySource {
    let subject = PassthroughSubject<[IslandActivity], Never>()
    var activitiesPublisher: AnyPublisher<[IslandActivity], Never> { subject.eraseToAnyPublisher() }
}

@MainActor
final class IslandCoordinatorTests: XCTestCase {
    private func activity(_ id: String, _ priority: Int = IslandActivity.Priority.nowPlayingPlaying) -> IslandActivity {
        IslandActivity(id: id, kind: .nowPlaying, priority: priority)
    }

    private func make(enabled: Bool = true) -> (IslandCoordinator, FakeSource) {
        let source = FakeSource()
        return (IslandCoordinator(sources: [source], isIslandEnabled: enabled, hoverDelay: 0.02), source)
    }

    private func wait(_ seconds: TimeInterval = 0.12) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    func testIdleWithoutActivities() {
        let (c, _) = make()
        XCTAssertEqual(c.mode, .idle)
    }

    func testCompactWithActivity() {
        let (c, s) = make()
        s.subject.send([activity("a")])
        XCTAssertEqual(c.mode, .compact)
    }

    func testToggleExpandsAndCollapsesBackToCompact() {
        let (c, s) = make()
        s.subject.send([activity("a")])
        c.toggleExpanded()
        XCTAssertEqual(c.mode, .expanded)
        c.toggleExpanded()
        XCTAssertEqual(c.mode, .compact)
    }

    func testSelectionMergesMultipleSources() {
        let s1 = FakeSource(), s2 = FakeSource()
        let c = IslandCoordinator(sources: [s1, s2], hoverDelay: 0.02)
        s1.subject.send([activity("a", 20)])
        s2.subject.send([activity("b", 100)])
        XCTAssertEqual(c.selection.primary?.id, "b")
        XCTAssertEqual(c.selection.secondary?.id, "a")
        s2.subject.send([])
        XCTAssertEqual(c.selection.primary?.id, "a")
    }

    func testHoverExpandsAfterDelay() async {
        let (c, s) = make()
        s.subject.send([activity("a")])
        c.pointerEntered()
        XCTAssertEqual(c.mode, .compact)
        await wait()
        XCTAssertEqual(c.mode, .expanded)
    }

    func testHoverLeftBeforeDelayDoesNotExpand() async {
        let (c, s) = make()
        s.subject.send([activity("a")])
        c.pointerEntered()
        c.pointerExited()
        await wait()
        XCTAssertEqual(c.mode, .compact)
    }

    func testHoverInIdleNeverExpands() async {
        let (c, _) = make()
        c.pointerEntered()
        await wait()
        XCTAssertEqual(c.mode, .idle)
    }

    func testPointerExitCollapsesWhenEntered() async {
        let (c, s) = make()
        s.subject.send([activity("a")])
        c.pointerEntered()
        await wait()
        XCTAssertEqual(c.mode, .expanded)
        c.pointerExited()
        XCTAssertEqual(c.mode, .compact)
    }

    func testHotkeyExpandedIsNotCollapsedByUnrelatedExit() {
        let (c, s) = make()
        s.subject.send([activity("a")])
        c.toggleExpanded()
        c.pointerExited()
        XCTAssertEqual(c.mode, .expanded)
    }

    func testToggleCancelsPendingHover() async {
        let (c, s) = make()
        s.subject.send([activity("a")])
        c.pointerEntered()
        c.toggleExpanded()
        XCTAssertEqual(c.mode, .expanded)
        await wait()
        c.toggleExpanded()
        XCTAssertEqual(c.mode, .compact)
        await wait()
        XCTAssertEqual(c.mode, .compact)
    }

    func testDisabledIslandNeverShowsCompact() {
        let (c, s) = make(enabled: false)
        s.subject.send([activity("a")])
        XCTAssertEqual(c.mode, .idle)
    }

    func testDisabledIslandCanStillBeExpandedByToggle() {
        let (c, s) = make(enabled: false)
        s.subject.send([activity("a")])
        c.toggleExpanded()
        XCTAssertEqual(c.mode, .expanded)
        c.toggleExpanded()
        XCTAssertEqual(c.mode, .idle)
    }

    func testOnExpandedChangedFiresOnToggle() {
        let (c, _) = make()
        var events: [Bool] = []
        c.onExpandedChanged = { events.append($0) }
        c.toggleExpanded()
        c.toggleExpanded()
        XCTAssertEqual(events, [true, false])
    }
}

#if canImport(XCTest)
import Combine
import XCTest
@testable import MeloDock

@MainActor
private final class FakeSource: ActivitySource {
    let subject = PassthroughSubject<[IslandActivity], Never>()
    var activitiesPublisher: AnyPublisher<[IslandActivity], Never> { subject.eraseToAnyPublisher() }
    let transients = PassthroughSubject<IslandTransient, Never>()
    var transientsPublisher: AnyPublisher<IslandTransient, Never> { transients.eraseToAnyPublisher() }
}

/// Manual clock and scheduler: nothing fires until the test says so.
@MainActor
private final class ManualClock {
    var now = Date(timeIntervalSinceReferenceDate: 5_000)
    private(set) var delays: [TimeInterval] = []
    private var fire: (@MainActor () -> Void)?
    private(set) var cancelled = 0

    func schedule(_ delay: TimeInterval, _ block: @escaping @MainActor () -> Void) -> AnyCancellable {
        delays.append(delay)
        fire = block
        return AnyCancellable { [weak self] in
            MainActor.assumeIsolated { self?.cancelled += 1 }
        }
    }

    func advance(_ seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
        fire?()
    }
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

    private func makeTransient(enabled: Bool = true) -> (IslandCoordinator, FakeSource, ManualClock) {
        let source = FakeSource()
        let clock = ManualClock()
        let c = IslandCoordinator(sources: [source], isIslandEnabled: enabled, hoverDelay: 0.02,
                                  now: { clock.now }, scheduler: { clock.schedule($0, $1) })
        return (c, source, clock)
    }

    private func transient(_ id: String, _ duration: TimeInterval = 2.5) -> IslandTransient {
        IslandTransient(id: id, kind: .audio, payload: .volume(0.5), duration: duration, sticky: false)
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

    func testToggleCollapseBeforeDelayDoesNotReExpandFromStaleHover() async {
        let (c, s) = make()
        s.subject.send([activity("a")])
        c.pointerEntered()
        c.toggleExpanded()
        c.toggleExpanded()
        XCTAssertEqual(c.mode, .compact)
        await wait()
        XCTAssertEqual(c.mode, .compact)
        XCTAssertFalse(c.isExpanded)
    }

    func testPointerExitCollapsesWhenEnteredWhileAlreadyExpanded() {
        let (c, s) = make()
        s.subject.send([activity("a")])
        c.toggleExpanded()
        c.pointerEntered()
        c.pointerExited()
        XCTAssertEqual(c.mode, .compact)
    }

    func testPointerExitDoesNotCollapseWhileTextFieldHasFocus() {
        let (c, s) = make()
        s.subject.send([activity("a")])
        c.toggleExpanded()
        c.pointerEntered()
        c.setTextEditing(true)
        c.pointerExited()
        XCTAssertTrue(c.isExpanded)
    }

    func testEndingTextEditingWithPointerOutsideCollapses() {
        let (c, s) = make()
        s.subject.send([activity("a")])
        c.toggleExpanded()
        c.pointerEntered()
        c.setTextEditing(true)
        c.pointerExited()
        c.setTextEditing(false)
        XCTAssertFalse(c.isExpanded)
    }

    func testEndingTextEditingWithPointerInsideStaysExpanded() {
        let (c, s) = make()
        s.subject.send([activity("a")])
        c.toggleExpanded()
        c.pointerEntered()
        c.setTextEditing(true)
        c.setTextEditing(false)
        XCTAssertTrue(c.isExpanded)
    }

    func testCollapsingResetsTextEditing() {
        let (c, s) = make()
        s.subject.send([activity("a")])
        c.toggleExpanded()
        c.setTextEditing(true)
        c.toggleExpanded()
        XCTAssertFalse(c.isTextEditing)
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

    // A click that lands just after the hover deadline must not collapse the island the hover just opened.
    func testExpandAfterHoverExpansionStaysExpanded() async {
        let (c, s) = make()
        s.subject.send([activity("a")])
        var events: [Bool] = []
        c.onExpandedChanged = { events.append($0) }
        c.pointerEntered()
        await wait()
        XCTAssertEqual(c.mode, .expanded)
        c.expand()
        XCTAssertEqual(c.mode, .expanded)
        XCTAssertEqual(events, [true])
    }

    func testExpandFromCompactExpandsAndCancelsPendingHover() async {
        let (c, s) = make()
        s.subject.send([activity("a")])
        var events: [Bool] = []
        c.onExpandedChanged = { events.append($0) }
        c.pointerEntered()
        c.expand()
        XCTAssertEqual(c.mode, .expanded)
        await wait()
        XCTAssertEqual(c.mode, .expanded)
        XCTAssertEqual(events, [true])
    }

    // MARK: - Transients

    func testModeFunctionPriority() {
        typealias C = IslandCoordinator
        XCTAssertEqual(C.mode(isExpanded: true, enabled: true, hasPrimary: true, hasTransient: true), .expanded)
        XCTAssertEqual(C.mode(isExpanded: true, enabled: false, hasPrimary: false, hasTransient: false), .expanded)
        XCTAssertEqual(C.mode(isExpanded: false, enabled: true, hasPrimary: true, hasTransient: true), .transient)
        XCTAssertEqual(C.mode(isExpanded: false, enabled: true, hasPrimary: false, hasTransient: true), .transient)
        XCTAssertEqual(C.mode(isExpanded: false, enabled: true, hasPrimary: true, hasTransient: false), .compact)
        XCTAssertEqual(C.mode(isExpanded: false, enabled: false, hasPrimary: true, hasTransient: true), .idle)
        XCTAssertEqual(C.mode(isExpanded: false, enabled: true, hasPrimary: false, hasTransient: false), .idle)
    }

    func testTransientShowsThenExpiresBackToCompact() {
        let (c, s, clock) = makeTransient()
        s.subject.send([activity("a")])
        s.transients.send(transient("volume"))
        XCTAssertEqual(c.transient?.id, "volume")
        XCTAssertEqual(c.mode, .transient)
        XCTAssertEqual(clock.delays.last ?? -1, 2.5, accuracy: 0.001)
        clock.advance(2.5)
        XCTAssertNil(c.transient)
        XCTAssertEqual(c.mode, .compact)
    }

    func testQueuedTransientsShowInOrder() {
        let (c, s, clock) = makeTransient()
        s.transients.send(transient("a"))
        s.transients.send(transient("b", 1))
        XCTAssertEqual(c.transient?.id, "a")
        clock.advance(2.5)
        XCTAssertEqual(c.transient?.id, "b")
        XCTAssertEqual(clock.delays.last ?? -1, 1, accuracy: 0.001)
        clock.advance(1)
        XCTAssertNil(c.transient)
        XCTAssertEqual(c.mode, .idle)
    }

    func testExpandedSuppressesTransient() {
        let (c, s, _) = makeTransient()
        s.subject.send([activity("a")])
        s.transients.send(transient("volume"))
        XCTAssertEqual(c.mode, .transient)
        c.expand()
        XCTAssertNil(c.transient)
        XCTAssertEqual(c.mode, .expanded)
        c.toggleExpanded()
        XCTAssertEqual(c.mode, .compact)
    }

    func testTransientArrivingWhileExpandedIsNotShown() {
        let (c, s, _) = makeTransient()
        s.subject.send([activity("a")])
        c.expand()
        s.transients.send(transient("volume"))
        XCTAssertNil(c.transient)
        c.toggleExpanded()
        XCTAssertEqual(c.mode, .compact)
    }

    func testDisabledIslandDropsTransients() {
        let (c, s, _) = makeTransient(enabled: false)
        s.transients.send(transient("volume"))
        XCTAssertNil(c.transient)
        XCTAssertEqual(c.mode, .idle)

        c.isIslandEnabled = true
        s.transients.send(transient("volume"))
        XCTAssertEqual(c.mode, .transient)
        c.isIslandEnabled = false
        XCTAssertNil(c.transient)
        XCTAssertEqual(c.mode, .idle)
        c.isIslandEnabled = true
        XCTAssertNil(c.transient)
    }

    func testSameIdTransientCoalescesAndReschedules() {
        let (c, s, clock) = makeTransient()
        s.transients.send(transient("volume"))
        clock.now = clock.now.addingTimeInterval(1)
        s.transients.send(transient("volume"))
        XCTAssertEqual(clock.delays.last ?? -1, 2.5, accuracy: 0.001)
        XCTAssertEqual(c.transient?.id, "volume")
    }

    // MARK: Tabs

    private func timerActivity() -> IslandActivity {
        IslandActivity(id: "timer", kind: .timer, priority: IslandActivity.Priority.timer, detail: .timer)
    }

    private func calendarActivity() -> IslandActivity {
        IslandActivity(id: "calendar", kind: .calendar, priority: IslandActivity.Priority.calendar, detail: .calendar)
    }

    func testCurrentPageFollowsPrimaryUntilPicked() {
        let (c, s) = make()
        s.subject.send([activity("nowPlaying"), timerActivity()])
        XCTAssertEqual(c.currentPage, .timer)
        c.expand()
        c.selectTab(.nowPlaying)
        XCTAssertEqual(c.selectedTab, .nowPlaying)
        XCTAssertEqual(c.currentPage, .nowPlaying)
    }

    func testSelectedTabResetsOnCollapseAndExpand() {
        let (c, s) = make()
        s.subject.send([activity("nowPlaying"), timerActivity()])
        c.expand()
        c.selectTab(.nowPlaying)
        c.toggleExpanded()
        XCTAssertNil(c.selectedTab)
        c.expand()
        c.selectTab(.nowPlaying)
        c.toggleExpanded()
        c.toggleExpanded()
        XCTAssertNil(c.selectedTab)
        XCTAssertEqual(c.currentPage, .timer)
    }

    func testPickedCalendarDropsWhenEventEnds() {
        let (c, s) = make()
        s.subject.send([activity("nowPlaying"), calendarActivity()])
        XCTAssertEqual(c.tabs, [.nowPlaying, .timer, .calendar])
        c.expand()
        c.selectTab(.calendar)
        XCTAssertEqual(c.currentPage, .calendar)
        s.subject.send([activity("nowPlaying")])
        XCTAssertNil(c.selectedTab)
        XCTAssertEqual(c.currentPage, .nowPlaying)
    }

    func testSelectingUnavailableTabIsIgnored() {
        let (c, _) = make()
        c.selectTab(.calendar)
        XCTAssertNil(c.selectedTab)
    }

    func testTimerTabHiddenWhenTimerDisabled() {
        let (c, _) = make()
        XCTAssertEqual(c.tabs, [.nowPlaying, .timer])
        c.enabledKinds = IslandKindFilter.all.subtracting([.timer])
        XCTAssertEqual(c.tabs, [.nowPlaying])
    }
}
#endif

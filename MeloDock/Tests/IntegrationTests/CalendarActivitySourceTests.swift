#if canImport(XCTest)
import AppKit
import Combine
import XCTest
@testable import MeloDock

@MainActor
private final class FakeCalendarProvider: CalendarEventProviding {
    let status = CurrentValueSubject<CalendarAuthorizationStatus, Never>(.notDetermined)
    let changes = PassthroughSubject<Void, Never>()
    var events: [CalendarEventInfo] = []
    var fetchCount = 0
    var accessResult = true
    var requestCount = 0

    var authorizationStatus: CalendarAuthorizationStatus { status.value }
    var authorizationStatusPublisher: AnyPublisher<CalendarAuthorizationStatus, Never> { status.eraseToAnyPublisher() }
    var changesPublisher: AnyPublisher<Void, Never> { changes.eraseToAnyPublisher() }

    func refreshAuthorizationStatus() {}

    func requestAccess() async -> Bool {
        requestCount += 1
        status.send(accessResult ? .authorized : .denied)
        return accessResult
    }

    func events(from: Date, to: Date) -> [CalendarEventInfo] {
        fetchCount += 1
        return events.filter { $0.start < to && $0.end > from }
    }
}

/// Mirrors the old service: `@Published` emits in willSet, and `events` guards on the stored value.
@MainActor
private final class WillSetOrderingProvider: CalendarEventProviding, ObservableObject {
    @Published private(set) var authorizationStatus: CalendarAuthorizationStatus = .notDetermined
    let changes = PassthroughSubject<Void, Never>()
    var events: [CalendarEventInfo] = []

    var authorizationStatusPublisher: AnyPublisher<CalendarAuthorizationStatus, Never> {
        $authorizationStatus.eraseToAnyPublisher()
    }
    var changesPublisher: AnyPublisher<Void, Never> { changes.eraseToAnyPublisher() }

    func setStatus(_ status: CalendarAuthorizationStatus) { authorizationStatus = status }
    func refreshAuthorizationStatus() {}
    func requestAccess() async -> Bool { true }
    func events(from: Date, to: Date) -> [CalendarEventInfo] {
        guard authorizationStatus == .authorized else { return [] }
        return events.filter { $0.start < to && $0.end > from }
    }
}

@MainActor
final class CalendarActivitySourceTests: XCTestCase {
    private var now = Date(timeIntervalSince1970: 100_000)
    private var scheduled: [(delay: TimeInterval, fire: @MainActor () -> Void, cancelled: Bool)] = []
    private var latest: [IslandActivity] = []
    private var bag = Set<AnyCancellable>()

    private func event(_ id: String, in seconds: TimeInterval) -> CalendarEventInfo {
        let start = now.addingTimeInterval(seconds)
        return CalendarEventInfo(id: id, title: "Standup", start: start, end: start.addingTimeInterval(1800),
                                 location: "Room 1", joinURL: nil)
    }

    private func makeSource(_ provider: FakeCalendarProvider) -> CalendarActivitySource {
        scheduled = []
        latest = []
        let source = CalendarActivitySource(
            provider: provider, now: { [unowned self] in self.now },
            scheduler: { [unowned self] delay, fire in
                self.scheduled.append((delay, fire, false))
                let index = self.scheduled.count - 1
                return AnyCancellable { self.scheduled[index].cancelled = true }
            })
        source.activitiesPublisher.sink { [unowned self] in self.latest = $0 }.store(in: &bag)
        return source
    }

    /// The source hops one main-queue turn on status changes; wait for it.
    private func settle() {
        let done = expectation(description: "main queue turn")
        DispatchQueue.main.async { done.fulfill() }
        wait(for: [done], timeout: 2)
    }

    private var liveTimers: [(delay: TimeInterval, fire: @MainActor () -> Void, cancelled: Bool)] {
        scheduled.filter { !$0.cancelled }
    }

    func testDoesNothingUntilAuthorized() {
        let provider = FakeCalendarProvider()
        provider.events = [event("a", in: 0)]
        let source = makeSource(provider)
        provider.changes.send()
        XCTAssertEqual(provider.fetchCount, 0)
        XCTAssertEqual(provider.requestCount, 0)
        XCTAssertTrue(latest.isEmpty)
        XCTAssertTrue(liveTimers.isEmpty)
        XCTAssertNil(source.activeEvent)
    }

    func testDeniedStaysQuiet() {
        let provider = FakeCalendarProvider()
        let source = makeSource(provider)
        provider.status.send(.denied)
        settle()
        XCTAssertEqual(provider.fetchCount, 0)
        XCTAssertNil(source.activeEvent)
    }

    func testAuthorizedWithEventInWindowShowsActivity() {
        let provider = FakeCalendarProvider()
        provider.events = [event("a", in: 300)]
        let source = makeSource(provider)
        provider.status.send(.authorized)
        settle()
        XCTAssertEqual(latest, [IslandActivity(id: "calendar", kind: .calendar,
                                               priority: IslandActivity.Priority.calendar, detail: .calendar)])
        XCTAssertEqual(source.activeEvent?.id, "a")
    }

    func testSchedulesOneWakeAtTheNextBoundaryAndShowsWhenItFires() {
        let provider = FakeCalendarProvider()
        provider.events = [event("a", in: 3600)]
        let source = makeSource(provider)
        provider.status.send(.authorized)
        settle()
        XCTAssertTrue(latest.isEmpty)
        XCTAssertEqual(liveTimers.count, 1)
        XCTAssertEqual(liveTimers[0].delay, 3000, accuracy: 0.001) // start - 10 min

        now = now.addingTimeInterval(3000)
        liveTimers[0].fire()
        XCTAssertEqual(latest.map(\.id), ["calendar"])
        XCTAssertEqual(source.activeEvent?.id, "a")
        XCTAssertEqual(liveTimers.count, 1)
        XCTAssertEqual(liveTimers[0].delay, 900, accuracy: 0.001) // start + 5 min

        now = now.addingTimeInterval(900)
        liveTimers[0].fire()
        XCTAssertTrue(latest.isEmpty)
        XCTAssertNil(source.activeEvent)
    }

    func testAuthorizationEmittedBeforeStoredStatusUpdatesStillLoadsEvents() {
        let provider = WillSetOrderingProvider()
        provider.events = [event("a", in: 60)]
        scheduled = []
        let source = CalendarActivitySource(
            provider: provider, now: { [unowned self] in self.now },
            scheduler: { [unowned self] delay, fire in
                self.scheduled.append((delay, fire, false))
                return AnyCancellable {}
            })
        provider.setStatus(.authorized)
        settle()
        XCTAssertEqual(source.activeEvent?.id, "a")
    }

    func testWakeClockTimeZoneAndDayChangeAllRefresh() {
        let provider = FakeCalendarProvider()
        let center = NotificationCenter()
        let workspace = NotificationCenter()
        scheduled = []
        let source = CalendarActivitySource(
            provider: provider, now: { [unowned self] in self.now },
            scheduler: { [unowned self] delay, fire in
                self.scheduled.append((delay, fire, false))
                let index = self.scheduled.count - 1
                return AnyCancellable { self.scheduled[index].cancelled = true }
            },
            notificationCenter: center, workspaceNotificationCenter: workspace)
        provider.status.send(.authorized)
        settle()
        var fetches = provider.fetchCount
        let posts: [(NotificationCenter, Notification.Name)] = [
            (workspace, NSWorkspace.didWakeNotification), (center, .NSSystemClockDidChange),
            (center, .NSSystemTimeZoneDidChange), (center, .NSCalendarDayChanged)]
        for (nc, name) in posts {
            provider.events = [event("n-\(name.rawValue)", in: 60)]
            nc.post(name: name, object: nil)
            settle()
            XCTAssertEqual(provider.fetchCount, fetches + 1, "\(name.rawValue) should refresh")
            XCTAssertEqual(source.activeEvent?.id, "n-\(name.rawValue)")
            fetches = provider.fetchCount
        }
        provider.status.send(.denied)
        settle()
        center.post(name: .NSSystemClockDidChange, object: nil)
        settle()
        XCTAssertEqual(provider.fetchCount, fetches, "no refresh once access is lost")
    }

    func testStoreChangeRefreshes() {
        let provider = FakeCalendarProvider()
        let source = makeSource(provider)
        provider.status.send(.authorized)
        settle()
        XCTAssertTrue(latest.isEmpty)
        provider.events = [event("new", in: 60)]
        provider.changes.send()
        XCTAssertEqual(source.activeEvent?.id, "new")
        XCTAssertEqual(liveTimers.count, 1)
    }

    func testLosingAuthorizationClearsAndCancelsTimer() {
        let provider = FakeCalendarProvider()
        provider.events = [event("a", in: 60)]
        let source = makeSource(provider)
        provider.status.send(.authorized)
        settle()
        XCTAssertNotNil(source.activeEvent)
        provider.status.send(.denied)
        settle()
        XCTAssertTrue(latest.isEmpty)
        XCTAssertNil(source.activeEvent)
        XCTAssertTrue(liveTimers.isEmpty)
        let fetches = provider.fetchCount
        provider.changes.send()
        XCTAssertEqual(provider.fetchCount, fetches)
    }

    func testIdleStillRechecksWithinAnHour() {
        let provider = FakeCalendarProvider()
        let source = makeSource(provider)
        provider.status.send(.authorized)
        settle()
        XCTAssertEqual(liveTimers.count, 1)
        XCTAssertLessThanOrEqual(liveTimers[0].delay, 3600)
        withExtendedLifetime(source) {}
    }
}
#endif

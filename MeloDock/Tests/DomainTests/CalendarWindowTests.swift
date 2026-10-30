#if canImport(XCTest)
import XCTest
@testable import MeloDock

final class CalendarWindowTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 10_000)

    private func event(_ id: String, start: Date, title: String = "Meeting") -> CalendarEventInfo {
        CalendarEventInfo(id: id, title: title, start: start, end: start.addingTimeInterval(3600),
                          location: nil, joinURL: nil)
    }

    func testHiddenJustBeforeTenMinutesAhead() {
        let e = event("a", start: start)
        XCTAssertNil(CalendarWindow.activeEvent(in: [e], now: start.addingTimeInterval(-600.001)))
    }

    func testShownExactlyTenMinutesBefore() {
        let e = event("a", start: start)
        XCTAssertEqual(CalendarWindow.activeEvent(in: [e], now: start.addingTimeInterval(-600)), e)
    }

    func testShownAtStartAndJustBeforeFiveMinutesAfter() {
        let e = event("a", start: start)
        XCTAssertEqual(CalendarWindow.activeEvent(in: [e], now: start), e)
        XCTAssertEqual(CalendarWindow.activeEvent(in: [e], now: start.addingTimeInterval(299.999)), e)
    }

    func testHiddenExactlyFiveMinutesAfterStart() {
        let e = event("a", start: start)
        XCTAssertNil(CalendarWindow.activeEvent(in: [e], now: start.addingTimeInterval(300)))
        XCTAssertNil(CalendarWindow.activeEvent(in: [e], now: start.addingTimeInterval(301)))
    }

    func testOverlapPicksEarliestStart() {
        let early = event("early", start: start)
        let late = event("late", start: start.addingTimeInterval(120))
        let now = start.addingTimeInterval(60)
        XCTAssertEqual(CalendarWindow.activeEvent(in: [late, early], now: now), early)
    }

    func testOverlapTieBrokenByIdAscending() {
        let b = event("b", start: start)
        let a = event("a", start: start)
        XCTAssertEqual(CalendarWindow.activeEvent(in: [b, a], now: start)?.id, "a")
    }

    func testEarlierEventDropsOutAndLaterTakesOver() {
        let early = event("early", start: start)
        let late = event("late", start: start.addingTimeInterval(400))
        let now = start.addingTimeInterval(350)
        XCTAssertEqual(CalendarWindow.activeEvent(in: [early, late], now: now), late)
    }

    func testNoEventsMeansNoActiveEvent() {
        XCTAssertNil(CalendarWindow.activeEvent(in: [], now: start))
    }

    func testNextWakeIsShowBoundaryOfUpcomingEvent() {
        let e = event("a", start: start)
        XCTAssertEqual(CalendarWindow.nextWakeDate(events: [e], now: start.addingTimeInterval(-3600)),
                       start.addingTimeInterval(-600))
    }

    func testNextWakeIsHideBoundaryWhileShowing() {
        let e = event("a", start: start)
        XCTAssertEqual(CalendarWindow.nextWakeDate(events: [e], now: start), start.addingTimeInterval(300))
    }

    func testNextWakeIsStrictlyAfterNow() {
        let e = event("a", start: start)
        XCTAssertEqual(CalendarWindow.nextWakeDate(events: [e], now: start.addingTimeInterval(-600)),
                       start.addingTimeInterval(300))
    }

    func testNextWakeChoosesEarliestAcrossEvents() {
        let a = event("a", start: start.addingTimeInterval(5000))
        let b = event("b", start: start)
        XCTAssertEqual(CalendarWindow.nextWakeDate(events: [a, b], now: start.addingTimeInterval(-5000)),
                       start.addingTimeInterval(-600))
    }

    func testNextWakeNilWhenAllInThePast() {
        let e = event("a", start: start)
        XCTAssertNil(CalendarWindow.nextWakeDate(events: [e], now: start.addingTimeInterval(300)))
        XCTAssertNil(CalendarWindow.nextWakeDate(events: [], now: start))
    }
}

final class CalendarJoinURLTests: XCTestCase {
    func testFindsZoomLinkInNotes() {
        let url = CalendarWindow.joinURL(from: [nil, "Agenda\nJoin: https://us02web.zoom.us/j/123456789?pwd=abc\nThanks"])
        XCTAssertEqual(url?.absoluteString, "https://us02web.zoom.us/j/123456789?pwd=abc")
    }

    func testFindsGoogleMeetInLocation() {
        let url = CalendarWindow.joinURL(from: ["https://meet.google.com/abc-defg-hij", nil])
        XCTAssertEqual(url?.host, "meet.google.com")
    }

    func testFindsTeamsLink() {
        let url = CalendarWindow.joinURL(from: ["Click <https://teams.microsoft.com/l/meetup-join/19%3ameeting_x/0> to join"])
        XCTAssertEqual(url?.host, "teams.microsoft.com")
    }

    func testFindsLinkInURLField() {
        let url = CalendarWindow.joinURL(from: [nil, nil, "https://zoom.us/j/42"])
        XCTAssertEqual(url?.absoluteString, "https://zoom.us/j/42")
    }

    func testIgnoresOtherLinks() {
        XCTAssertNil(CalendarWindow.joinURL(from: ["See https://example.com/zoom.us/j/1 and https://notzoom.us/j/2"]))
    }

    func testSkipsOtherLinksBeforeAMeetingLink() {
        let url = CalendarWindow.joinURL(from: ["Docs https://example.com/doc then https://meet.google.com/xyz-abcd-efg"])
        XCTAssertEqual(url?.host, "meet.google.com")
    }

    func testNoTextsMeansNoURL() {
        XCTAssertNil(CalendarWindow.joinURL(from: []))
        XCTAssertNil(CalendarWindow.joinURL(from: [nil, ""]))
    }
}
#endif

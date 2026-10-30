#if canImport(XCTest)
import XCTest
@testable import MeloDock

final class IslandTimeFormatTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 10_000)

    func testClockMinutesSeconds() {
        XCTAssertEqual(IslandTimeFormat.clock(0), "0:00")
        XCTAssertEqual(IslandTimeFormat.clock(5), "0:05")
        XCTAssertEqual(IslandTimeFormat.clock(65), "1:05")
        XCTAssertEqual(IslandTimeFormat.clock(25 * 60), "25:00")
        XCTAssertEqual(IslandTimeFormat.clock(3599.9), "59:59")
    }

    func testClockHours() {
        XCTAssertEqual(IslandTimeFormat.clock(3600), "1:00:00")
        XCTAssertEqual(IslandTimeFormat.clock(3600 + 125), "1:02:05")
        XCTAssertEqual(IslandTimeFormat.clock(10 * 3600 + 59 * 60 + 59), "10:59:59")
    }

    func testClockClampsNegative() {
        XCTAssertEqual(IslandTimeFormat.clock(-4), "0:00")
    }

    func testMinutesUntilRoundsUp() {
        XCTAssertEqual(IslandTimeFormat.minutesUntil(t0.addingTimeInterval(600), now: t0), 10)
        XCTAssertEqual(IslandTimeFormat.minutesUntil(t0.addingTimeInterval(541), now: t0), 10)
        XCTAssertEqual(IslandTimeFormat.minutesUntil(t0.addingTimeInterval(59), now: t0), 1)
        XCTAssertEqual(IslandTimeFormat.minutesUntil(t0.addingTimeInterval(1), now: t0), 1)
    }

    func testMinutesUntilIsZeroOnceStarted() {
        XCTAssertEqual(IslandTimeFormat.minutesUntil(t0, now: t0), 0)
        XCTAssertEqual(IslandTimeFormat.minutesUntil(t0, now: t0.addingTimeInterval(200)), 0)
    }

    func testCalendarEarText() {
        XCTAssertEqual(IslandTimeFormat.calendarEar(start: t0.addingTimeInterval(300), now: t0), "5m")
        XCTAssertEqual(IslandTimeFormat.calendarEar(start: t0, now: t0), "Now")
        XCTAssertEqual(IslandTimeFormat.calendarEar(start: t0, now: t0.addingTimeInterval(120)), "Now")
    }

    func testTimerEarsCountdownRoundsUpRemaining() {
        let c = TimerEarsContent.make(countdown: .running(endsAt: t0.addingTimeInterval(60)), stopwatch: .idle, now: t0.addingTimeInterval(0.4))
        XCTAssertEqual(c, TimerEarsContent(style: .countdown, text: "1:00", isPaused: false))
    }

    func testTimerEarsPausedAndFinished() {
        XCTAssertEqual(TimerEarsContent.make(countdown: .paused(remaining: 90), stopwatch: .idle, now: t0),
                       TimerEarsContent(style: .countdown, text: "1:30", isPaused: true))
        XCTAssertEqual(TimerEarsContent.make(countdown: .finished(at: t0), stopwatch: .idle, now: t0)?.style, .finished)
        XCTAssertEqual(TimerEarsContent.make(countdown: .finished(at: t0), stopwatch: .idle, now: t0)?.text, "Done")
    }

    func testTimerEarsStopwatchElapsed() {
        let running = TimerEarsContent.make(countdown: .idle, stopwatch: .running(startedAt: t0, accumulated: 30),
                                            now: t0.addingTimeInterval(35))
        XCTAssertEqual(running, TimerEarsContent(style: .stopwatch, text: "1:05", isPaused: false))
        XCTAssertEqual(TimerEarsContent.make(countdown: .idle, stopwatch: .paused(elapsed: 7), now: t0)?.isPaused, true)
        XCTAssertNil(TimerEarsContent.make(countdown: .idle, stopwatch: .idle, now: t0))
    }

    func testCountdownWinsOverStopwatch() {
        let c = TimerEarsContent.make(countdown: .paused(remaining: 10), stopwatch: .running(startedAt: t0, accumulated: 0), now: t0)
        XCTAssertEqual(c?.style, .countdown)
    }

    func testFlashAlternatesPerSecond() {
        let a = TimerEarsContent.isFlashOn(at: Date(timeIntervalSinceReferenceDate: 100.2))
        let b = TimerEarsContent.isFlashOn(at: Date(timeIntervalSinceReferenceDate: 101.2))
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(a, TimerEarsContent.isFlashOn(at: Date(timeIntervalSinceReferenceDate: 100.9)))
    }
}
#endif

#if canImport(XCTest)
import Combine
import XCTest
@testable import MeloDock

@MainActor
final class TimerModelTests: XCTestCase {
    private final class Clock {
        var date = Date(timeIntervalSince1970: 1_000)
        func advance(_ seconds: TimeInterval) { date = date.addingTimeInterval(seconds) }
    }

    private var clock = Clock()
    private var sounds = 0
    private var transients: [IslandTransient] = []
    private var cancellables = Set<AnyCancellable>()

    private func makeModel() -> TimerModel {
        clock = Clock()
        sounds = 0
        transients = []
        let model = TimerModel(now: { [clock] in clock.date }, playSound: { [weak self] in self?.sounds += 1 },
                               startsTicker: false)
        model.transientsPublisher.sink { [weak self] in self?.transients.append($0) }.store(in: &cancellables)
        return model
    }

    private func advance(_ model: TimerModel, _ seconds: TimeInterval) {
        clock.advance(seconds)
        model.tick(now: clock.date)
    }

    func testCountdownReachingZeroFiresOneTransientAndFinishes() {
        let model = makeModel()
        model.startCountdown(duration: 60)
        XCTAssertEqual(model.countdown, .running(endsAt: clock.date.addingTimeInterval(60)))
        advance(model, 59)
        XCTAssertTrue(transients.isEmpty)
        advance(model, 1)
        XCTAssertEqual(transients.count, 1)
        XCTAssertEqual(transients.first?.payload, .timerDone)
        XCTAssertEqual(transients.first?.kind, .timer)
        XCTAssertEqual(transients.first?.sticky, false)
        XCTAssertEqual(model.countdown, .finished(at: clock.date))
        advance(model, 1)
        advance(model, 1)
        XCTAssertEqual(transients.count, 1)
    }

    func testPauseAndResumeKeepRemaining() {
        let model = makeModel()
        model.startCountdown(duration: 60)
        advance(model, 20)
        model.pauseCountdown()
        XCTAssertEqual(model.countdown, .paused(remaining: 40))
        advance(model, 500)
        XCTAssertTrue(transients.isEmpty)
        XCTAssertEqual(model.countdown, .paused(remaining: 40))
        model.resumeCountdown()
        XCTAssertEqual(model.countdown, .running(endsAt: clock.date.addingTimeInterval(40)))
        advance(model, 40)
        XCTAssertEqual(transients.count, 1)
    }

    func testCancelReturnsToIdleWithoutTransient() {
        let model = makeModel()
        model.startCountdown(duration: 10)
        model.cancelCountdown()
        XCTAssertEqual(model.countdown, .idle)
        advance(model, 20)
        XCTAssertTrue(transients.isEmpty)
    }

    func testSoundPlaysOnFinishThenEveryThreeSecondsUntilThirty() {
        let model = makeModel()
        model.startCountdown(duration: 5)
        advance(model, 5)
        XCTAssertEqual(sounds, 1)
        advance(model, 2)
        XCTAssertEqual(sounds, 1)
        advance(model, 1)
        XCTAssertEqual(sounds, 2)
        for _ in 0..<26 { advance(model, 1) } // 29s after finishing
        XCTAssertEqual(sounds, 10)
        advance(model, 1) // 30s after finishing
        advance(model, 10)
        XCTAssertEqual(sounds, 10)
        if case .finished = model.countdown {} else { XCTFail("stays finished until dismissed") }
    }

    func testDismissStopsSoundAndClearsFinished() {
        let model = makeModel()
        model.startCountdown(duration: 5)
        advance(model, 5)
        model.dismissFinished()
        XCTAssertEqual(model.countdown, .idle)
        advance(model, 10)
        XCTAssertEqual(sounds, 1)
    }

    func testStartingNewCountdownStopsFinishedSound() {
        let model = makeModel()
        model.startCountdown(duration: 5)
        advance(model, 5)
        model.startCountdown(duration: 100)
        advance(model, 10)
        XCTAssertEqual(sounds, 1)
    }

    func testStopwatchRunPauseResumeReset() {
        let model = makeModel()
        model.startStopwatch()
        advance(model, 10)
        XCTAssertEqual(model.stopwatchElapsed(now: clock.date), 10)
        model.pauseStopwatch()
        XCTAssertEqual(model.stopwatch, .paused(elapsed: 10))
        advance(model, 100)
        XCTAssertEqual(model.stopwatchElapsed(now: clock.date), 10)
        model.startStopwatch()
        advance(model, 5)
        XCTAssertEqual(model.stopwatchElapsed(now: clock.date), 15)
        model.resetStopwatch()
        XCTAssertEqual(model.stopwatch, .idle)
        XCTAssertEqual(model.stopwatchElapsed(now: clock.date), 0)
    }

    func testCountdownAndStopwatchAreIndependent() {
        let model = makeModel()
        model.startCountdown(duration: 30)
        model.startStopwatch()
        advance(model, 10)
        model.pauseCountdown()
        advance(model, 10)
        XCTAssertEqual(model.countdown, .paused(remaining: 20))
        XCTAssertEqual(model.stopwatchElapsed(now: clock.date), 20)
        model.resetStopwatch()
        XCTAssertEqual(model.countdown, .paused(remaining: 20))
        model.startStopwatch()
        model.cancelCountdown()
        XCTAssertEqual(model.stopwatch, .running(startedAt: clock.date, accumulated: 0))
    }

    func testZeroOrNegativeDurationIsIgnored() {
        let model = makeModel()
        model.startCountdown(duration: 0)
        model.startCountdown(duration: -5)
        XCTAssertEqual(model.countdown, .idle)
    }
}

@MainActor
final class TimerActivitySourceTests: XCTestCase {
    private final class Box {
        var value: [IslandActivity] = []
        var bag = Set<AnyCancellable>()
    }

    private func makeModel() -> (TimerModel, TimerActivitySource, () -> [IslandActivity]) {
        let model = TimerModel(now: { Date(timeIntervalSince1970: 0) }, playSound: {}, startsTicker: false)
        let source = TimerActivitySource(model: model)
        let box = Box()
        source.activitiesPublisher.sink { box.value = $0 }.store(in: &box.bag)
        return (model, source, { box.value })
    }

    func testIdleModelHasNoActivity() {
        let (_, source, latest) = makeModel(); defer { withExtendedLifetime(source) {} }
        XCTAssertTrue(latest().isEmpty)
    }

    func testCountdownStatesMapToStableTimerActivity() {
        let (model, source, latest) = makeModel(); defer { withExtendedLifetime(source) {} }
        model.startCountdown(duration: 60)
        XCTAssertEqual(latest(), [IslandActivity(id: "timer", kind: .timer, priority: IslandActivity.Priority.timer, detail: .timer)])
        model.pauseCountdown()
        XCTAssertEqual(latest().map(\.id), ["timer"])
        model.cancelCountdown()
        XCTAssertTrue(latest().isEmpty)
    }

    func testStopwatchRunningMapsPausedDoesNot() {
        let (model, source, latest) = makeModel(); defer { withExtendedLifetime(source) {} }
        model.startStopwatch()
        XCTAssertEqual(latest().first?.priority, IslandActivity.Priority.timer)
        model.pauseStopwatch()
        XCTAssertTrue(latest().isEmpty)
    }

    func testFinishedKeepsActivityUntilDismissed() {
        let (model, source, latest) = makeModel(); defer { withExtendedLifetime(source) {} }
        model.startCountdown(duration: 1)
        model.tick(now: Date(timeIntervalSince1970: 2))
        XCTAssertEqual(latest().map(\.id), ["timer"])
        model.dismissFinished()
        XCTAssertTrue(latest().isEmpty)
    }

    func testForwardsTimerDoneTransient() {
        let (model, source, _) = makeModel()
        var received: [IslandTransient] = []
        let c = source.transientsPublisher.sink { received.append($0) }
        model.startCountdown(duration: 1)
        model.tick(now: Date(timeIntervalSince1970: 2))
        XCTAssertEqual(received.map(\.payload), [.timerDone])
        c.cancel()
    }
}
#endif

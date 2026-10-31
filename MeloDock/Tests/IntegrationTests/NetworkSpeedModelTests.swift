#if canImport(XCTest)
import Combine
import XCTest
@testable import MeloDock

@MainActor
final class NetworkSpeedModelTests: XCTestCase {
    private final class FakeReader: NetworkCounterReading {
        var counters: [String: NetworkCounters] = [:]
        func read() -> [String: NetworkCounters] { counters }
    }

    private var clock = Date(timeIntervalSinceReferenceDate: 50_000)
    private let reader = FakeReader()

    private func makeModel() -> NetworkSpeedModel {
        NetworkSpeedModel(reader: reader, now: { [unowned self] in clock })
    }

    private func set(_ received: UInt32, _ sent: UInt32) {
        reader.counters = ["en0": NetworkCounters(received: received, sent: sent)]
    }

    func testFirstSampleOnlyTakesABaseline() {
        let model = makeModel()
        set(1_000, 1_000)
        model.sample()
        XCTAssertEqual(model.speed, .zero)
    }

    func testSecondSamplePublishesTheRate() {
        let model = makeModel()
        set(1_000, 100)
        model.sample()
        clock.addTimeInterval(1)
        set(3_000, 400)
        model.sample()
        XCTAssertEqual(model.speed, NetworkSpeed(download: 2_000, upload: 300))
    }

    func testRateFollowsTheActualElapsedTime() {
        let model = makeModel()
        set(0, 0)
        model.sample()
        clock.addTimeInterval(2)
        set(1_000, 1_000)
        model.sample()
        XCTAssertEqual(model.speed, NetworkSpeed(download: 500, upload: 500))
    }

    func testIdleNetworkReadsZeroAgain() {
        let model = makeModel()
        set(0, 0)
        model.sample()
        clock.addTimeInterval(1)
        set(5_000, 0)
        model.sample()
        clock.addTimeInterval(1)
        model.sample()
        XCTAssertEqual(model.speed, .zero)
    }

    func testStartingTakesABaselineAndStoppingClearsTheSpeed() {
        let model = makeModel()
        set(0, 0)
        model.setRunning(true)
        XCTAssertTrue(model.isRunning)
        clock.addTimeInterval(1)
        set(1_000, 0)
        model.sample()
        XCTAssertEqual(model.speed.download, 1_000)

        model.setRunning(false)
        XCTAssertFalse(model.isRunning)
        XCTAssertEqual(model.speed, .zero)
    }

    func testRestartDoesNotMeasureAcrossThePause() {
        let model = makeModel()
        set(0, 0)
        model.setRunning(true)
        model.setRunning(false)
        clock.addTimeInterval(600)
        set(900_000_000, 0)
        model.setRunning(true)
        defer { model.setRunning(false) }
        XCTAssertEqual(model.speed, .zero)
    }

    func testSettingTheSameRunningStateTwiceIsHarmless() {
        let model = makeModel()
        model.setRunning(true)
        model.setRunning(true)
        XCTAssertTrue(model.isRunning)
        model.setRunning(false)
        model.setRunning(false)
        XCTAssertFalse(model.isRunning)
    }
}

@MainActor
final class NetworkActivitySourceTests: XCTestCase {
    private final class FakeReader: NetworkCounterReading {
        func read() -> [String: NetworkCounters] { [:] }
    }

    func testPublishesTheNetworkActivity() {
        let model = NetworkSpeedModel(reader: FakeReader())
        let source = NetworkActivitySource(model: model, isEnabled: Just(false).eraseToAnyPublisher())
        var latest: [IslandActivity] = []
        let c = source.activitiesPublisher.sink { latest = $0 }
        defer { c.cancel() }
        XCTAssertEqual(latest, [NetworkActivitySource.activity])
        XCTAssertEqual(latest.first?.kind, .network)
    }

    func testSamplingFollowsTheSwitch() {
        let model = NetworkSpeedModel(reader: FakeReader())
        let enabled = CurrentValueSubject<Bool, Never>(false)
        let source = NetworkActivitySource(model: model, isEnabled: enabled.eraseToAnyPublisher())
        XCTAssertFalse(model.isRunning)
        enabled.send(true)
        XCTAssertTrue(model.isRunning)
        enabled.send(false)
        XCTAssertFalse(model.isRunning)
        withExtendedLifetime(source) {}
    }
}
#endif

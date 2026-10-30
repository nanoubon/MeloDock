#if canImport(XCTest)
import Combine
import XCTest
@testable import MeloDock

final class PowerStateMapperTests: XCTestCase {
    private func s(_ p: Int, charging: Bool = false, plugged: Bool = false) -> PowerState {
        PowerState(percent: p, isCharging: charging, isPluggedIn: plugged, hasBattery: true)
    }

    func testFirstReadingEmitsNothing() {
        XCTAssertTrue(PowerEventMapper.events(from: nil, to: s(50, charging: true, plugged: true)).isEmpty)
        XCTAssertTrue(PowerEventMapper.events(from: nil, to: s(5)).isEmpty)
    }

    func testNoBatteryEmitsNothing() {
        XCTAssertTrue(PowerEventMapper.events(from: .noBattery, to: .noBattery).isEmpty)
        XCTAssertTrue(PowerEventMapper.events(from: s(50), to: .noBattery).isEmpty)
    }

    func testPlugInStartsCharging() {
        let e = PowerEventMapper.events(from: s(50), to: s(50, charging: true, plugged: true))
        XCTAssertEqual(e.count, 1)
        XCTAssertEqual(e[0].id, PowerEventMapper.chargingID)
        XCTAssertEqual(e[0].kind, .power)
        XCTAssertEqual(e[0].payload, .charging(percent: 50, isCharging: true))
    }

    func testPlugInWhileFullEmitsNotCharging() {
        let e = PowerEventMapper.events(from: s(100), to: s(100, charging: false, plugged: true))
        XCTAssertEqual(e.first?.payload, .charging(percent: 100, isCharging: false))
    }

    func testChargingContinuesEmitsNothing() {
        XCTAssertTrue(PowerEventMapper.events(from: s(50, charging: true, plugged: true),
                                              to: s(51, charging: true, plugged: true)).isEmpty)
    }

    func testUnplugEmitsNothing() {
        XCTAssertTrue(PowerEventMapper.events(from: s(50, charging: true, plugged: true), to: s(50)).isEmpty)
    }

    func testLowAt20() {
        let e = PowerEventMapper.events(from: s(21), to: s(20))
        XCTAssertEqual(e.count, 1)
        XCTAssertEqual(e[0].id, PowerEventMapper.lowBatteryID)
        XCTAssertEqual(e[0].payload, .batteryLow(percent: 20))
    }

    func testLowAt10() {
        XCTAssertEqual(PowerEventMapper.events(from: s(11), to: s(10)).first?.payload, .batteryLow(percent: 10))
    }

    func testCrossingBothEmitsOnce() {
        XCTAssertEqual(PowerEventMapper.events(from: s(25), to: s(8)).count, 1)
    }

    func testNotRepeatedBelowThreshold() {
        XCTAssertTrue(PowerEventMapper.events(from: s(19), to: s(18)).isEmpty)
        XCTAssertTrue(PowerEventMapper.events(from: s(20), to: s(19)).isEmpty)
        XCTAssertTrue(PowerEventMapper.events(from: s(9), to: s(8)).isEmpty)
    }

    func testNoLowWhileCharging() {
        XCTAssertTrue(PowerEventMapper.events(from: s(21, charging: true, plugged: true),
                                              to: s(20, charging: true, plugged: true)).isEmpty)
    }

    func testRisingNeverEmitsLow() {
        XCTAssertTrue(PowerEventMapper.events(from: s(9), to: s(21)).isEmpty)
    }

    @MainActor
    func testSourceEmitsTransientsAndNoActivities() {
        let subject = PassthroughSubject<PowerState, Never>()
        let source = PowerActivitySource(states: subject.eraseToAnyPublisher())
        var got: [IslandTransient] = []
        var activities: [[IslandActivity]] = []
        let c1 = source.transientsPublisher.sink { got.append($0) }
        let c2 = source.activitiesPublisher.sink { activities.append($0) }
        subject.send(s(50))
        subject.send(s(50, charging: true, plugged: true))
        subject.send(s(50, charging: false, plugged: false))
        subject.send(s(20))
        XCTAssertEqual(got.map(\.id), [PowerEventMapper.chargingID, PowerEventMapper.lowBatteryID])
        XCTAssertTrue(activities.isEmpty)
        withExtendedLifetime((c1, c2)) {}
    }
}
#endif

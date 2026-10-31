#if canImport(XCTest)
import XCTest
@testable import MeloDock

final class NetworkSpeedFormatTests: XCTestCase {
    func testShortBelowOneKilobyte() {
        XCTAssertEqual(NetworkSpeedFormat.short(0), "0")
        XCTAssertEqual(NetworkSpeedFormat.short(0.4), "0")
        XCTAssertEqual(NetworkSpeedFormat.short(1), "1B")
        XCTAssertEqual(NetworkSpeedFormat.short(850), "850B")
        XCTAssertEqual(NetworkSpeedFormat.short(999.4), "999B")
    }

    func testShortUnitBoundaries() {
        XCTAssertEqual(NetworkSpeedFormat.short(999.5), "1.0K")
        XCTAssertEqual(NetworkSpeedFormat.short(1_000), "1.0K")
        XCTAssertEqual(NetworkSpeedFormat.short(1_234), "1.2K")
        XCTAssertEqual(NetworkSpeedFormat.short(9_940), "9.9K")
        XCTAssertEqual(NetworkSpeedFormat.short(9_960), "10K")
        XCTAssertEqual(NetworkSpeedFormat.short(12_345), "12K")
        XCTAssertEqual(NetworkSpeedFormat.short(999_400), "999K")
        XCTAssertEqual(NetworkSpeedFormat.short(999_600), "1.0M")
    }

    func testShortLargeUnits() {
        XCTAssertEqual(NetworkSpeedFormat.short(1_200_000), "1.2M")
        XCTAssertEqual(NetworkSpeedFormat.short(15_000_000), "15M")
        XCTAssertEqual(NetworkSpeedFormat.short(1_100_000_000), "1.1G")
        XCTAssertEqual(NetworkSpeedFormat.short(250_000_000_000), "250G")
    }

    func testShortIgnoresNegativeAndNonFiniteValues() {
        XCTAssertEqual(NetworkSpeedFormat.short(-5), "0")
        XCTAssertEqual(NetworkSpeedFormat.short(.nan), "0")
        XCTAssertEqual(NetworkSpeedFormat.short(.infinity), "0")
    }

    func testSpokenWording() {
        XCTAssertEqual(NetworkSpeedFormat.spoken(0), "0 bytes per second")
        XCTAssertEqual(NetworkSpeedFormat.spoken(850), "850 bytes per second")
        XCTAssertEqual(NetworkSpeedFormat.spoken(80_000), "80 kilobytes per second")
        XCTAssertEqual(NetworkSpeedFormat.spoken(1_200_000), "1.2 megabytes per second")
    }
}

final class NetworkSpeedCalculatorTests: XCTestCase {
    private func counters(_ received: UInt32, _ sent: UInt32) -> NetworkCounters {
        NetworkCounters(received: received, sent: sent)
    }

    func testRateIsDeltaOverInterval() {
        let speed = NetworkSpeedCalculator.speed(from: ["en0": counters(1_000, 500)],
                                                 to: ["en0": counters(4_000, 800)], interval: 2)
        XCTAssertEqual(speed, NetworkSpeed(download: 1_500, upload: 150))
    }

    func testSumsInterfacesPresentInBothSamples() {
        let speed = NetworkSpeedCalculator.speed(
            from: ["en0": counters(0, 0), "en5": counters(100, 100)],
            to: ["en0": counters(1_000, 0), "en5": counters(300, 150), "en6": counters(9_999, 9_999)],
            interval: 1)
        XCTAssertEqual(speed, NetworkSpeed(download: 1_200, upload: 50))
    }

    func testCounterWrapIsNotAJump() {
        let speed = NetworkSpeedCalculator.speed(from: ["en0": counters(UInt32.max - 99, UInt32.max)],
                                                 to: ["en0": counters(100, 9)], interval: 1)
        XCTAssertEqual(speed, NetworkSpeed(download: 200, upload: 10))
    }

    func testCounterResetFromALowValueCountsAsNoTraffic() {
        let speed = NetworkSpeedCalculator.speed(from: ["en0": counters(1_000_000, 2_000_000)],
                                                 to: ["en0": counters(500, 700)], interval: 1)
        XCTAssertEqual(speed, .zero)
    }

    func testNonPositiveIntervalGivesZero() {
        let a = ["en0": counters(0, 0)]
        let b = ["en0": counters(1_000, 1_000)]
        XCTAssertEqual(NetworkSpeedCalculator.speed(from: a, to: b, interval: 0), .zero)
        XCTAssertEqual(NetworkSpeedCalculator.speed(from: a, to: b, interval: -1), .zero)
    }

    func testEmptySamplesGiveZero() {
        XCTAssertEqual(NetworkSpeedCalculator.speed(from: [:], to: [:], interval: 1), .zero)
    }
}

final class SystemNetworkCounterReaderTests: XCTestCase {
    func testOnlyEthernetAndWifiInterfacesCount() {
        XCTAssertTrue(SystemNetworkCounterReader.isPhysical("en0"))
        XCTAssertTrue(SystemNetworkCounterReader.isPhysical("en12"))
        XCTAssertFalse(SystemNetworkCounterReader.isPhysical("utun3"))
        XCTAssertFalse(SystemNetworkCounterReader.isPhysical("awdl0"))
        XCTAssertFalse(SystemNetworkCounterReader.isPhysical("llw0"))
        XCTAssertFalse(SystemNetworkCounterReader.isPhysical("bridge0"))
        XCTAssertFalse(SystemNetworkCounterReader.isPhysical("lo0"))
        XCTAssertFalse(SystemNetworkCounterReader.isPhysical("en"))
        XCTAssertFalse(SystemNetworkCounterReader.isPhysical("enc0"))
    }

    func testReadingLiveCountersReturnsOnlyPhysicalInterfaces() {
        let counters = SystemNetworkCounterReader().read()
        XCTAssertTrue(counters.keys.allSatisfy(SystemNetworkCounterReader.isPhysical))
    }
}
#endif

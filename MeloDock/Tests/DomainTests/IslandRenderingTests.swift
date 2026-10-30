#if canImport(XCTest)
import XCTest
@testable import MeloDock

final class IslandRenderingTests: XCTestCase {
    private func make(_ payload: IslandTransient.Payload) -> SystemAlertContent {
        SystemAlertContent.make(from: IslandTransient(id: "x", kind: .audio, payload: payload, duration: 3, sticky: false))
    }

    func testCharging() {
        let c = make(.charging(percent: 80, isCharging: true))
        XCTAssertEqual(c.symbol, "bolt.fill")
        XCTAssertEqual(c.trailing, .text("80%"))
        XCTAssertEqual(c.tone, .positive)
    }

    func testPluggedInNotCharging() {
        XCTAssertEqual(make(.charging(percent: 100, isCharging: false)).symbol, "powerplug.fill")
    }

    func testBatteryLowToneEscalatesAtTen() {
        XCTAssertEqual(make(.batteryLow(percent: 20)).tone, .warning)
        XCTAssertEqual(make(.batteryLow(percent: 10)).tone, .critical)
    }

    func testPercentIsClamped() {
        XCTAssertEqual(make(.charging(percent: 140, isCharging: true)).trailing, .text("100%"))
        XCTAssertEqual(make(.batteryLow(percent: -3)).trailing, .text("0%"))
    }

    func testBluetoothShowsNameAndState() {
        let on = make(.bluetooth(name: "AirPods", connected: true))
        XCTAssertEqual(on.trailing, .text("AirPods"))
        XCTAssertEqual(on.accessibilityLabel, "AirPods connected")
        let off = make(.bluetooth(name: "AirPods", connected: false))
        XCTAssertEqual(off.symbol, "headphones.slash")
        XCTAssertEqual(off.accessibilityLabel, "AirPods disconnected")
    }

    func testVolumeBarAndSymbolSteps() {
        XCTAssertEqual(make(.volume(0.5)).trailing, .bar(0.5))
        XCTAssertEqual(make(.volume(2)).trailing, .bar(1))
        XCTAssertEqual(make(.volume(-1)).trailing, .bar(0))
        XCTAssertEqual(SystemAlertContent.volumeSymbol(0), "speaker.slash.fill")
        XCTAssertEqual(SystemAlertContent.volumeSymbol(0.2), "speaker.wave.1.fill")
        XCTAssertEqual(SystemAlertContent.volumeSymbol(0.5), "speaker.wave.2.fill")
        XCTAssertEqual(SystemAlertContent.volumeSymbol(0.9), "speaker.wave.3.fill")
        XCTAssertEqual(make(.volume(0.5)).accessibilityLabel, "Volume 50 percent")
    }

    func testOutputAndTimerDone() {
        XCTAssertEqual(make(.output(name: "Speakers")).trailing, .text("Speakers"))
        XCTAssertEqual(make(.timerDone).trailing, .text("Done"))
    }

    func testCaptureEars() {
        XCTAssertTrue(CaptureEars.glyphs(mic: true, camera: false) == (nil, .mic))
        XCTAssertTrue(CaptureEars.glyphs(mic: false, camera: true) == (nil, .camera))
        XCTAssertTrue(CaptureEars.glyphs(mic: true, camera: true) == (.camera, .mic))
        XCTAssertTrue(CaptureEars.glyphs(mic: false, camera: false) == (nil, nil))
    }

    func testCompactContentRouting() {
        let playing = IslandActivity(id: "nowPlaying", kind: .nowPlaying, priority: 60)
        let capture = IslandActivity(id: "capture", kind: .capture, priority: 40, detail: .capture(mic: true, camera: false))
        let timer = IslandActivity(id: "t", kind: .timer, priority: 100, detail: .timer)
        XCTAssertEqual(CompactContent.make(for: playing), .nowPlaying)
        XCTAssertEqual(CompactContent.make(for: capture), .capture(mic: true, camera: false))
        XCTAssertEqual(CompactContent.make(for: timer), .empty)
        XCTAssertEqual(CompactContent.make(for: nil), .empty)
    }
}
#endif

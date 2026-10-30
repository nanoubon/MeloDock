#if canImport(XCTest)
import XCTest
@testable import MeloDock

final class TimerInputTests: XCTestCase {
    func testPresets() {
        XCTAssertEqual(TimerInput.presetMinutes, [1, 5, 10, 25])
    }

    func testParsesWholeMinutes() {
        XCTAssertEqual(TimerInput.duration(fromMinutes: "7"), 420)
        XCTAssertEqual(TimerInput.duration(fromMinutes: " 25 "), 1500)
        XCTAssertEqual(TimerInput.duration(fromMinutes: "999"), 999 * 60)
    }

    func testRejectsInvalidInput() {
        for text in ["", "  ", "0", "-5", "abc", "1.5", "1000", "5m"] {
            XCTAssertNil(TimerInput.duration(fromMinutes: text), text)
        }
    }
}
#endif

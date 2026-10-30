#if canImport(XCTest)
import XCTest
@testable import MeloDock

final class ScrubRailMathTests: XCTestCase {
    func testClampedKeepsValuesInUnitRange() {
        XCTAssertEqual(ScrubRailMath.clamped(-0.2), 0)
        XCTAssertEqual(ScrubRailMath.clamped(0.4), 0.4)
        XCTAssertEqual(ScrubRailMath.clamped(1.7), 1)
        XCTAssertEqual(ScrubRailMath.clamped(.nan), 0)
        XCTAssertEqual(ScrubRailMath.clamped(.infinity), 0)
    }

    func testFractionAtXClampsToRail() {
        XCTAssertEqual(ScrubRailMath.fraction(atX: 28, width: 112), 0.25)
        XCTAssertEqual(ScrubRailMath.fraction(atX: -10, width: 112), 0)
        XCTAssertEqual(ScrubRailMath.fraction(atX: 200, width: 112), 1)
    }

    func testFractionAtXWithZeroWidthIsZero() {
        XCTAssertEqual(ScrubRailMath.fraction(atX: 5, width: 0), 0)
    }

    func testFilledWidthIsZeroAtZero() {
        XCTAssertEqual(ScrubRailMath.filledWidth(fraction: 0, width: 100, railHeight: 4), 0)
    }

    func testFilledWidthNeverNarrowerThanRailHeight() {
        XCTAssertEqual(ScrubRailMath.filledWidth(fraction: 0.01, width: 100, railHeight: 4), 4)
        XCTAssertEqual(ScrubRailMath.filledWidth(fraction: 0.5, width: 100, railHeight: 4), 50)
        XCTAssertEqual(ScrubRailMath.filledWidth(fraction: 2, width: 100, railHeight: 4), 100)
    }

    func testKnobCenterStaysInsideRail() {
        XCTAssertEqual(ScrubRailMath.knobCenterX(fraction: 0, width: 100, knobSize: 12), 6)
        XCTAssertEqual(ScrubRailMath.knobCenterX(fraction: 0.5, width: 100, knobSize: 12), 50)
        XCTAssertEqual(ScrubRailMath.knobCenterX(fraction: 1, width: 100, knobSize: 12), 94)
    }

    func testKnobCenterOnRailNarrowerThanKnob() {
        XCTAssertEqual(ScrubRailMath.knobCenterX(fraction: 0.8, width: 10, knobSize: 12), 5)
    }

    func testSteppedClamps() {
        XCTAssertEqual(ScrubRailMath.stepped(0.98, by: 0.05), 1)
        XCTAssertEqual(ScrubRailMath.stepped(0.02, by: -0.05), 0)
        XCTAssertEqual(ScrubRailMath.stepped(0.5, by: 0.05), 0.55, accuracy: 1e-9)
    }
}
#endif

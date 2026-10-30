#if canImport(XCTest)
import XCTest
@testable import MeloDock

final class IslandShapeMetricsTests: XCTestCase {
    private let notch = NotchGeometry(centerX: 756, width: 200, height: 32)

    func testIdleWithNotchMatchesNotch() {
        XCTAssertEqual(IslandShapeMetrics.size(for: .idle, notch: notch), CGSize(width: 200, height: 32))
    }

    func testCompactWithNotchAddsEars() {
        XCTAssertEqual(IslandShapeMetrics.size(for: .compact, notch: notch), CGSize(width: 312, height: 32))
    }

    func testExpandedWithNotchAddsNotchHeight() {
        XCTAssertEqual(IslandShapeMetrics.size(for: .expanded, notch: notch), CGSize(width: 612, height: 208))
    }

    func testIdleWithoutNotchIsZero() {
        XCTAssertEqual(IslandShapeMetrics.size(for: .idle, notch: nil), .zero)
    }

    func testCompactWithoutNotchIsPill() {
        XCTAssertEqual(IslandShapeMetrics.size(for: .compact, notch: nil), CGSize(width: 220, height: 34))
    }

    func testExpandedWithoutNotch() {
        XCTAssertEqual(IslandShapeMetrics.size(for: .expanded, notch: nil), CGSize(width: 612, height: 176))
    }

    func testHitRectIsCenteredAndTopFlush() {
        let rect = IslandShapeMetrics.hitRect(
            panelFrame: CGRect(x: 100, y: 200, width: 640, height: 200),
            size: CGSize(width: 300, height: 40))
        XCTAssertEqual(rect, CGRect(x: 270, y: 360, width: 300, height: 40))
    }
}
#endif

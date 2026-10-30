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
        XCTAssertEqual(IslandShapeMetrics.size(for: .expanded, notch: notch), CGSize(width: 612, height: 220))
    }

    func testIdleWithoutNotchIsZero() {
        XCTAssertEqual(IslandShapeMetrics.size(for: .idle, notch: nil), .zero)
    }

    func testCompactWithoutNotchIsPill() {
        XCTAssertEqual(IslandShapeMetrics.size(for: .compact, notch: nil), CGSize(width: 220, height: 34))
    }

    func testExpandedWithoutNotch() {
        XCTAssertEqual(IslandShapeMetrics.size(for: .expanded, notch: nil), CGSize(width: 612, height: 188))
    }

    func testTransientMatchesCompactSize() {
        XCTAssertEqual(IslandShapeMetrics.size(for: .transient, notch: notch),
                       IslandShapeMetrics.size(for: .compact, notch: notch))
        XCTAssertEqual(IslandShapeMetrics.size(for: .transient, notch: nil),
                       IslandShapeMetrics.size(for: .compact, notch: nil))
    }

    func testHitRectIsCenteredAndTopFlush() {
        let rect = IslandShapeMetrics.hitRect(
            panelFrame: CGRect(x: 100, y: 200, width: 640, height: 200),
            size: CGSize(width: 300, height: 40))
        XCTAssertEqual(rect, CGRect(x: 270, y: 360, width: 300, height: 40))
    }

    // MARK: Secondary circle

    private let panel = CGRect(x: 100, y: 200, width: 640, height: 260)

    func testSecondaryCircleSizeMatchesCompactHeight() {
        XCTAssertEqual(IslandShapeMetrics.secondaryCircleSize(notch: notch), 32)
        XCTAssertEqual(IslandShapeMetrics.secondaryCircleSize(notch: nil), 34)
    }

    func testSecondaryFrameSitsRightOfIslandAtSameHeight() {
        // Island is 312 wide centered at x=420: spans 264...576, top edge at y=460.
        let frame = IslandShapeMetrics.secondaryFrame(panelFrame: panel, mode: .compact, notch: notch, hasSecondary: true)
        XCTAssertEqual(frame, CGRect(x: 576 + IslandShapeMetrics.secondaryGap, y: 460 - 32, width: 32, height: 32))
    }

    func testSecondaryFrameAlsoShownDuringTransient() {
        XCTAssertNotNil(IslandShapeMetrics.secondaryFrame(panelFrame: panel, mode: .transient, notch: notch, hasSecondary: true))
    }

    func testSecondaryFrameNilWithoutSecondaryOrWhenIdleOrExpanded() {
        XCTAssertNil(IslandShapeMetrics.secondaryFrame(panelFrame: panel, mode: .compact, notch: notch, hasSecondary: false))
        XCTAssertNil(IslandShapeMetrics.secondaryFrame(panelFrame: panel, mode: .idle, notch: notch, hasSecondary: true))
        XCTAssertNil(IslandShapeMetrics.secondaryFrame(panelFrame: panel, mode: .expanded, notch: notch, hasSecondary: true))
    }

    func testSecondaryFrameFitsInsidePanelForWideNotches() {
        let panelFrame = CGRect(x: 0, y: 0, width: IslandShapeMetrics.panelWidth, height: 260)
        for width in [180.0, 200, 240, 300] {
            let wide = NotchGeometry(centerX: 320, width: width, height: 38)
            let frame = IslandShapeMetrics.secondaryFrame(panelFrame: panelFrame, mode: .compact, notch: wide, hasSecondary: true)
            XCTAssertNotNil(frame)
            XCTAssertLessThanOrEqual(frame!.maxX, panelFrame.maxX, "notch width \(width)")
        }
        let pill = IslandShapeMetrics.secondaryFrame(panelFrame: panelFrame, mode: .compact, notch: nil, hasSecondary: true)
        XCTAssertLessThanOrEqual(pill!.maxX, panelFrame.maxX)
    }
}
#endif

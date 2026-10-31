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

    func testCompactEarsAreWiderOnlyForMusicSharingWithNetwork() {
        let playing = IslandActivity(id: "np", kind: .nowPlaying, priority: IslandActivity.Priority.nowPlayingPlaying)
        let timer = IslandActivity(id: "timer", kind: .timer, priority: IslandActivity.Priority.timer, detail: .timer)
        let wide = IslandShapeMetrics.musicNetworkEarWidth
        XCTAssertEqual(IslandShapeMetrics.compactEarWidth(primary: playing, networkEnabled: true), wide)
        XCTAssertEqual(IslandShapeMetrics.compactEarWidth(primary: playing, networkEnabled: false),
                       IslandShapeMetrics.earWidth)
        XCTAssertEqual(IslandShapeMetrics.compactEarWidth(primary: timer, networkEnabled: true),
                       IslandShapeMetrics.earWidth)
        XCTAssertEqual(IslandShapeMetrics.compactEarWidth(primary: NetworkActivitySource.activity, networkEnabled: true),
                       IslandShapeMetrics.earWidth)
        XCTAssertEqual(IslandShapeMetrics.compactEarWidth(primary: nil, networkEnabled: true),
                       IslandShapeMetrics.earWidth)
    }

    func testWiderCompactEarsGrowNotchedShapeButNotThePillOrOtherModes() {
        let wide = IslandShapeMetrics.musicNetworkEarWidth
        let grown = IslandShapeMetrics.size(for: .compact, notch: notch, transient: nil, compactEarWidth: wide)
        XCTAssertEqual(grown, CGSize(width: 200 + 2 * wide, height: 32))
        XCTAssertEqual(IslandShapeMetrics.size(for: .compact, notch: nil, transient: nil, compactEarWidth: wide),
                       IslandShapeMetrics.pillSize)
        XCTAssertEqual(IslandShapeMetrics.size(for: .expanded, notch: notch, transient: nil, compactEarWidth: wide),
                       IslandShapeMetrics.size(for: .expanded, notch: notch))
        XCTAssertLessThanOrEqual(grown.width + 2 * (32 + IslandShapeMetrics.secondaryGap), IslandShapeMetrics.panelWidth)
    }

    func testSecondaryCircleFollowsTheWiderCompactIsland() {
        let panel = CGRect(x: 436, y: 600, width: 640, height: 300)
        let wide = IslandShapeMetrics.musicNetworkEarWidth
        let standard = IslandShapeMetrics.secondaryFrame(panelFrame: panel, mode: .compact, notch: notch, hasSecondary: true)!
        let grown = IslandShapeMetrics.secondaryFrame(panelFrame: panel, mode: .compact, notch: notch, hasSecondary: true,
                                                      compactEarWidth: wide)!
        XCTAssertEqual(grown.minX - standard.minX, wide - IslandShapeMetrics.earWidth)
    }

    func testExpandedWithNotchAddsNotchHeight() {
        XCTAssertEqual(IslandShapeMetrics.size(for: .expanded, notch: notch), CGSize(width: 612, height: 252))
    }

    func testExpandedFitsPanelWithShadowRoomForTallNotch() {
        let tall = NotchGeometry(centerX: 320, width: 200, height: 44)
        let height = IslandShapeMetrics.size(for: .expanded, notch: tall).height
        XCTAssertLessThanOrEqual(height + 24, IslandShapeMetrics.panelHeight)
        XCTAssertLessThanOrEqual(IslandShapeMetrics.expandedSize.width, IslandShapeMetrics.panelWidth)
    }

    func testPageAndTabStripFillExpandedContent() {
        XCTAssertEqual(IslandShapeMetrics.pageHeight + IslandShapeMetrics.tabStripHeight, IslandShapeMetrics.expandedSize.height)
        XCTAssertGreaterThanOrEqual(IslandShapeMetrics.tabStripHeight, 28)
    }

    func testIdleWithoutNotchIsZero() {
        XCTAssertEqual(IslandShapeMetrics.size(for: .idle, notch: nil), .zero)
    }

    func testCompactWithoutNotchIsPill() {
        XCTAssertEqual(IslandShapeMetrics.size(for: .compact, notch: nil), CGSize(width: 220, height: 34))
    }

    func testExpandedWithoutNotch() {
        XCTAssertEqual(IslandShapeMetrics.size(for: .expanded, notch: nil), CGSize(width: 612, height: 220))
    }

    func testStandardTransientMatchesCompactSize() {
        for payload in [IslandTransient.Payload.volume(0.5), .charging(percent: 5, isCharging: true), .timerDone, .batteryLow(percent: 20)] {
            XCTAssertEqual(IslandShapeMetrics.size(for: .transient, notch: notch, transient: payload),
                           IslandShapeMetrics.size(for: .compact, notch: notch))
            XCTAssertEqual(IslandShapeMetrics.size(for: .transient, notch: nil, transient: payload),
                           IslandShapeMetrics.size(for: .compact, notch: nil))
        }
        XCTAssertEqual(IslandShapeMetrics.size(for: .transient, notch: notch),
                       IslandShapeMetrics.size(for: .compact, notch: notch))
    }

    func testNamePayloadsWidenTransientBothEars() {
        let compact = IslandShapeMetrics.size(for: .compact, notch: notch)
        let extra = 2 * (IslandShapeMetrics.nameEarWidth - IslandShapeMetrics.earWidth)
        for payload in [IslandTransient.Payload.bluetooth(name: "AirPods Pro", connected: true), .output(name: "MacBook Speakers")] {
            let size = IslandShapeMetrics.size(for: .transient, notch: notch, transient: payload)
            XCTAssertEqual(size.width, compact.width + extra)
            XCTAssertEqual(size.height, compact.height)
        }
        XCTAssertGreaterThan(IslandShapeMetrics.nameEarWidth, IslandShapeMetrics.earWidth)
    }

    func testPayloadIgnoredOutsideTransientMode() {
        let name = IslandTransient.Payload.output(name: "X")
        XCTAssertEqual(IslandShapeMetrics.size(for: .compact, notch: notch, transient: name),
                       IslandShapeMetrics.size(for: .compact, notch: notch))
    }

    func testWidenedTransientAndSecondaryStayInsidePanel() {
        let panelFrame = CGRect(x: 0, y: 0, width: IslandShapeMetrics.panelWidth, height: IslandShapeMetrics.panelHeight)
        let name = IslandTransient.Payload.bluetooth(name: "A very long headphone name", connected: true)
        for width in [180.0, 200, 240, 300] {
            let wide = NotchGeometry(centerX: 320, width: width, height: 38)
            let island = IslandShapeMetrics.hitRect(panelFrame: panelFrame,
                                                    size: IslandShapeMetrics.size(for: .transient, notch: wide, transient: name))
            XCTAssertGreaterThanOrEqual(island.minX, panelFrame.minX, "notch width \(width)")
            let frame = IslandShapeMetrics.secondaryFrame(panelFrame: panelFrame, mode: .transient, notch: wide,
                                                          hasSecondary: true, transient: name)
            XCTAssertNotNil(frame)
            XCTAssertLessThanOrEqual(frame!.maxX, panelFrame.maxX, "notch width \(width)")
        }
        let pill = IslandShapeMetrics.secondaryFrame(panelFrame: panelFrame, mode: .transient, notch: nil,
                                                     hasSecondary: true, transient: name)
        XCTAssertLessThanOrEqual(pill!.maxX, panelFrame.maxX)
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

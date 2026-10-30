#if canImport(XCTest)
import XCTest
@testable import MeloDock

final class NotchGeometryTests: XCTestCase {
    private let frame = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let left = CGRect(x: 0, y: 950, width: 656, height: 32)
    private let right = CGRect(x: 856, y: 950, width: 656, height: 32)

    private func make(
        frame: CGRect? = nil,
        safeAreaTop: CGFloat = 32,
        scale: CGFloat = 1,
        left: CGRect?? = nil,
        right: CGRect?? = nil,
        fallback: CGFloat = 756
    ) -> NotchGeometry? {
        NotchGeometry.make(
            screenFrame: frame ?? self.frame,
            safeAreaTop: safeAreaTop,
            backingScale: scale,
            auxLeft: left ?? self.left,
            auxRight: right ?? self.right,
            fallbackCenterX: fallback
        )
    }

    func testGlobalCoordinates() {
        XCTAssertEqual(make(), NotchGeometry(centerX: 756, width: 200, height: 32))
    }

    func testLocalCoordinatesOnSecondScreen() {
        let result = make(frame: CGRect(x: 1512, y: 0, width: 1512, height: 982), fallback: 2268)
        XCTAssertEqual(result?.centerX, 2268)
        XCTAssertEqual(result?.width, 200)
    }

    func testBackingSpaceRects() {
        let result = make(
            scale: 2,
            left: .some(CGRect(x: 0, y: 1900, width: 1312, height: 64)),
            right: .some(CGRect(x: 1712, y: 1900, width: 1312, height: 64))
        )
        XCTAssertEqual(result?.centerX, 756)
        XCTAssertEqual(result?.width, 200)
    }

    func testNilWithoutAuxiliaryAreas() {
        XCTAssertNil(make(left: .some(nil), right: .some(nil)))
    }

    func testNilWhenCenterFarFromFallback() {
        XCTAssertNil(make(fallback: 300))
    }

    func testNilWhenAreasOverlap() {
        XCTAssertNil(make(right: .some(CGRect(x: 600, y: 950, width: 912, height: 32))))
    }

    func testNilWhenSafeAreaTopIsZero() {
        XCTAssertNil(make(safeAreaTop: 0))
    }
}
#endif

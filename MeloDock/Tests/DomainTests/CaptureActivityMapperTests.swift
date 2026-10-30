#if canImport(XCTest)
import Combine
import XCTest
@testable import MeloDock

final class CaptureActivityMapperTests: XCTestCase {
    func testNothingInUseIsNil() {
        XCTAssertNil(CaptureActivityMapper.activity(micInUse: false, cameraInUse: false))
    }

    func testMicOnly() {
        let a = CaptureActivityMapper.activity(micInUse: true, cameraInUse: false)
        XCTAssertEqual(a, IslandActivity(id: "capture", kind: .capture, priority: IslandActivity.Priority.capture,
                                         detail: .capture(mic: true, camera: false)))
    }

    func testCameraOnlyAndBoth() {
        XCTAssertEqual(CaptureActivityMapper.activity(micInUse: false, cameraInUse: true)?.detail,
                       .capture(mic: false, camera: true))
        let both = CaptureActivityMapper.activity(micInUse: true, cameraInUse: true)
        XCTAssertEqual(both?.detail, .capture(mic: true, camera: true))
        XCTAssertEqual(both?.id, "capture")
        XCTAssertEqual(both?.priority, 40)
    }

    @MainActor
    func testSourcePublishesActivities() {
        let subject = PassthroughSubject<CaptureUsage, Never>()
        let source = CaptureActivitySource(usage: subject.eraseToAnyPublisher())
        var got: [[IslandActivity]] = []
        let c = source.activitiesPublisher.sink { got.append($0) }
        subject.send(CaptureUsage(mic: true, camera: false))
        subject.send(CaptureUsage(mic: false, camera: false))
        XCTAssertEqual(got.map(\.count), [0, 1, 0])
        withExtendedLifetime(c) {}
    }
}
#endif

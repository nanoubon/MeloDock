#if canImport(XCTest)
import Combine
import XCTest
@testable import MeloDock

@MainActor
private final class BareSource: ActivitySource {
    var activitiesPublisher: AnyPublisher<[IslandActivity], Never> {
        Just([]).eraseToAnyPublisher()
    }
}

final class IslandTransientTests: XCTestCase {
    func testActivityDetailDefaultsToNowPlaying() {
        let a = IslandActivity(id: "a", kind: .nowPlaying, priority: 1)
        XCTAssertEqual(a.detail, .nowPlaying)
    }

    func testActivityDetailParticipatesInEquality() {
        let a = IslandActivity(id: "c", kind: .capture, priority: 1, detail: .capture(mic: true, camera: false))
        let b = IslandActivity(id: "c", kind: .capture, priority: 1, detail: .capture(mic: true, camera: true))
        XCTAssertNotEqual(a, b)
    }

    func testTransientIsEquatableAndIdentifiable() {
        let t = IslandTransient(id: "volume", kind: .audio, payload: .volume(0.5), duration: 2.5, sticky: false)
        XCTAssertEqual(t.id, "volume")
        XCTAssertEqual(t, IslandTransient(id: "volume", kind: .audio, payload: .volume(0.5), duration: 2.5, sticky: false))
        XCTAssertNotEqual(t, IslandTransient(id: "volume", kind: .audio, payload: .volume(0.6), duration: 2.5, sticky: false))
    }

    @MainActor
    func testSourceDefaultTransientsPublisherNeverEmits() {
        let source = BareSource()
        var received: [IslandTransient] = []
        var finished = false
        let c = source.transientsPublisher.sink(receiveCompletion: { _ in finished = true },
                                                receiveValue: { received.append($0) })
        XCTAssertTrue(received.isEmpty)
        XCTAssertTrue(finished)
        c.cancel()
    }
}
#endif

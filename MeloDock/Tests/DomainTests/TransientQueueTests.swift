#if canImport(XCTest)
import XCTest
@testable import MeloDock

final class TransientQueueTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000)

    private func item(_ id: String, _ duration: TimeInterval = 2.5, sticky: Bool = false,
                      payload: IslandTransient.Payload = .timerDone) -> IslandTransient {
        IslandTransient(id: id, kind: .audio, payload: payload, duration: duration, sticky: sticky)
    }

    func testEmptyQueueHasNoCurrent() {
        var q = TransientQueue()
        XCTAssertNil(q.current)
        XCTAssertNil(q.expiresAt)
        XCTAssertFalse(q.tick(now: t0))
    }

    func testFirstEnqueueBecomesCurrentImmediately() {
        var q = TransientQueue()
        q.enqueue(item("a"), now: t0)
        XCTAssertEqual(q.current?.id, "a")
        XCTAssertEqual(q.expiresAt, t0.addingTimeInterval(2.5))
    }

    func testFIFOAdvancesOnExpiry() {
        var q = TransientQueue()
        q.enqueue(item("a"), now: t0)
        q.enqueue(item("b", 1), now: t0)
        q.enqueue(item("c"), now: t0)
        XCTAssertEqual(q.current?.id, "a")
        XCTAssertFalse(q.tick(now: t0.addingTimeInterval(2.4)))
        XCTAssertEqual(q.current?.id, "a")
        XCTAssertTrue(q.tick(now: t0.addingTimeInterval(2.5)))
        XCTAssertEqual(q.current?.id, "b")
        // The next item's clock starts when it becomes current, using its own duration.
        XCTAssertEqual(q.expiresAt, t0.addingTimeInterval(3.5))
        XCTAssertTrue(q.tick(now: t0.addingTimeInterval(3.5)))
        XCTAssertEqual(q.current?.id, "c")
        XCTAssertTrue(q.tick(now: t0.addingTimeInterval(6)))
        XCTAssertNil(q.current)
        XCTAssertFalse(q.tick(now: t0.addingTimeInterval(7)))
    }

    func testSameIdReplacesCurrentAndRestartsClock() {
        var q = TransientQueue()
        q.enqueue(item("volume", payload: .volume(0.2)), now: t0)
        q.enqueue(item("volume", payload: .volume(0.4)), now: t0.addingTimeInterval(1))
        XCTAssertEqual(q.current?.payload, .volume(0.4))
        XCTAssertEqual(q.expiresAt, t0.addingTimeInterval(3.5))
        XCTAssertFalse(q.tick(now: t0.addingTimeInterval(3.4)))
    }

    func testSameIdReplacesPendingInPlace() {
        var q = TransientQueue()
        q.enqueue(item("a"), now: t0)
        q.enqueue(item("b", payload: .volume(0.1)), now: t0)
        q.enqueue(item("c"), now: t0)
        q.enqueue(item("b", payload: .volume(0.9)), now: t0)
        XCTAssertEqual(q.pending.map(\.id), ["b", "c"])
        XCTAssertEqual(q.pending.first?.payload, .volume(0.9))
    }

    func testPendingCapDropsOldestPending() {
        var q = TransientQueue()
        q.enqueue(item("cur"), now: t0)
        for i in 1...7 { q.enqueue(item("p\(i)"), now: t0) }
        XCTAssertEqual(q.current?.id, "cur")
        XCTAssertEqual(q.pending.map(\.id), ["p3", "p4", "p5", "p6", "p7"])
    }

    func testTouchExtendsStickyItem() {
        var q = TransientQueue()
        q.enqueue(item("s", 2, sticky: true), now: t0)
        q.touch(id: "s", now: t0.addingTimeInterval(1.5))
        XCTAssertEqual(q.expiresAt, t0.addingTimeInterval(3.5))
        XCTAssertFalse(q.tick(now: t0.addingTimeInterval(3.4)))
        XCTAssertTrue(q.tick(now: t0.addingTimeInterval(3.5)))
    }

    func testTouchIgnoresNonStickyAndOtherIds() {
        var q = TransientQueue()
        q.enqueue(item("n", 2), now: t0)
        q.touch(id: "n", now: t0.addingTimeInterval(1))
        XCTAssertEqual(q.expiresAt, t0.addingTimeInterval(2))
        var s = TransientQueue()
        s.enqueue(item("s", 2, sticky: true), now: t0)
        s.touch(id: "other", now: t0.addingTimeInterval(1))
        XCTAssertEqual(s.expiresAt, t0.addingTimeInterval(2))
    }

    func testClearDropsEverything() {
        var q = TransientQueue()
        q.enqueue(item("a"), now: t0)
        q.enqueue(item("b"), now: t0)
        q.clear()
        XCTAssertNil(q.current)
        XCTAssertTrue(q.pending.isEmpty)
        XCTAssertNil(q.expiresAt)
    }

    func testEnqueueAfterDrainBecomesCurrent() {
        var q = TransientQueue()
        q.enqueue(item("a"), now: t0)
        _ = q.tick(now: t0.addingTimeInterval(3))
        q.enqueue(item("b"), now: t0.addingTimeInterval(4))
        XCTAssertEqual(q.current?.id, "b")
        XCTAssertEqual(q.expiresAt, t0.addingTimeInterval(6.5))
    }
}
#endif

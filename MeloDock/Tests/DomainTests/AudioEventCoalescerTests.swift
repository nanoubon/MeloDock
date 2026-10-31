#if canImport(XCTest)
import Combine
import XCTest
@testable import MeloDock

final class AudioEventCoalescerTests: XCTestCase {
    func testVolumeOnlyBatchNeedsNoRefresh() {
        XCTAssertFalse(AudioEventCoalescer.needsDeviceRefresh([.volumeChanged(0.2), .volumeChanged(0.3)]))
        XCTAssertFalse(AudioEventCoalescer.needsDeviceRefresh([]))
    }

    func testOutputOrDefaultChangeNeedsRefresh() {
        XCTAssertTrue(AudioEventCoalescer.needsDeviceRefresh([.volumeChanged(0.2), .outputsChanged]))
        XCTAssertTrue(AudioEventCoalescer.needsDeviceRefresh([.defaultOutputChanged]))
    }

    func testVolumePayloadIsExtracted() {
        XCTAssertEqual(AudioEventCoalescer.volume(in: .volumeChanged(0.7)), 0.7)
        XCTAssertNil(AudioEventCoalescer.volume(in: .outputsChanged))
    }

    func testBurstCoalescesToOneTriggerAndVolumeNeverTriggers() {
        let subject = PassthroughSubject<AudioDeviceEvent, Never>()
        var triggers = 0
        let cancellable = AudioEventCoalescer.refreshTriggers(
            subject.eraseToAnyPublisher(), scheduler: DispatchQueue.main, window: .milliseconds(30))
            .sink { triggers += 1 }
        subject.send(.volumeChanged(0.1))
        subject.send(.outputsChanged)
        subject.send(.defaultOutputChanged)
        subject.send(.volumeChanged(0.2))
        let done = expectation(description: "window elapsed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { done.fulfill() }
        wait(for: [done], timeout: 2)
        XCTAssertEqual(triggers, 1)

        subject.send(.volumeChanged(0.5))
        let done2 = expectation(description: "volume window elapsed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { done2.fulfill() }
        wait(for: [done2], timeout: 2)
        XCTAssertEqual(triggers, 1)
        cancellable.cancel()
    }
}
#endif

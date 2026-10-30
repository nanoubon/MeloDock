#if canImport(XCTest)
import Combine
import XCTest
@testable import MeloDock

final class AudioEventMapperTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func out(_ id: String, current: Bool = false, bt: Bool = false) -> AudioOutput {
        AudioOutput(id: id, name: "Dev \(id)", isCurrent: current, isBluetooth: bt)
    }

    private func run(old: [AudioOutput]?, new: [AudioOutput], oldVolume: Float? = nil, newVolume: Float? = nil,
                     switchedAt: Date? = nil, after: TimeInterval = 10) -> [IslandTransient] {
        AudioEventMapper.transients(old: old, new: new, oldVolume: oldVolume, newVolume: newVolume,
                                    now: t0.addingTimeInterval(after), lastOutputSwitchAt: switchedAt ?? t0.addingTimeInterval(-100))
    }

    func testInitialLoadEmitsNothing() {
        XCTAssertTrue(run(old: nil, new: [out("1", current: true), out("2", bt: true)], oldVolume: nil, newVolume: 0.7).isEmpty)
    }

    func testBluetoothConnected() {
        let e = run(old: [out("1", current: true)], new: [out("1", current: true), out("2", bt: true)])
        XCTAssertEqual(e.count, 1)
        XCTAssertEqual(e[0].id, "bluetooth.2")
        XCTAssertEqual(e[0].kind, .audio)
        XCTAssertEqual(e[0].payload, .bluetooth(name: "Dev 2", connected: true))
    }

    func testBluetoothDisconnected() {
        let e = run(old: [out("1", current: true), out("2", bt: true)], new: [out("1", current: true)])
        XCTAssertEqual(e.first?.payload, .bluetooth(name: "Dev 2", connected: false))
    }

    func testNonBluetoothAddRemoveIgnored() {
        XCTAssertTrue(run(old: [out("1", current: true)], new: [out("1", current: true), out("2")]).isEmpty)
    }

    func testDefaultOutputChanged() {
        let e = run(old: [out("1", current: true), out("2")], new: [out("1"), out("2", current: true)])
        XCTAssertEqual(e.count, 1)
        XCTAssertEqual(e[0].id, "audio.output")
        XCTAssertEqual(e[0].payload, .output(name: "Dev 2"))
    }

    func testSameOutputNoEvent() {
        let o = [out("1", current: true)]
        XCTAssertTrue(run(old: o, new: o).isEmpty)
    }

    func testVolumeChangeIsStickyAndStableID() {
        let o = [out("1", current: true)]
        let e = run(old: o, new: o, oldVolume: 0.5, newVolume: 0.6)
        XCTAssertEqual(e.count, 1)
        XCTAssertEqual(e[0].id, "audio.volume")
        XCTAssertEqual(e[0].payload, .volume(0.6))
        XCTAssertTrue(e[0].sticky)
    }

    func testUnchangedVolumeNoEvent() {
        let o = [out("1", current: true)]
        XCTAssertTrue(run(old: o, new: o, oldVolume: 0.5, newVolume: 0.5).isEmpty)
    }

    func testFirstVolumeReadingIsBaseline() {
        let o = [out("1", current: true)]
        XCTAssertTrue(run(old: o, new: o, oldVolume: nil, newVolume: 0.5).isEmpty)
    }

    func testVolumeSuppressedWithinHalfSecondOfOutputSwitch() {
        let o = [out("1", current: true)]
        XCTAssertTrue(run(old: o, new: o, oldVolume: 0.5, newVolume: 0.3, switchedAt: t0, after: 0.4).isEmpty)
        XCTAssertEqual(run(old: o, new: o, oldVolume: 0.5, newVolume: 0.3, switchedAt: t0, after: 0.5).count, 1)
    }

    func testVolumeSuppressedWhenOutputChangesInSameCall() {
        let e = run(old: [out("1", current: true), out("2")], new: [out("1"), out("2", current: true)],
                    oldVolume: 0.5, newVolume: 0.9)
        XCTAssertEqual(e.map(\.id), ["audio.output"])
    }

    @MainActor
    func testSourceEmitsFromProvider() {
        final class Fake: AudioDeviceProvider {
            let outputs = CurrentValueSubject<[AudioOutput], Never>([])
            let volume = CurrentValueSubject<Float, Never>(0.5)
            let events = PassthroughSubject<AudioDeviceEvent, Never>()
            var outputsPublisher: AnyPublisher<[AudioOutput], Never> { outputs.eraseToAnyPublisher() }
            var volumePublisher: AnyPublisher<Float, Never> { volume.eraseToAnyPublisher() }
            var eventsPublisher: AnyPublisher<AudioDeviceEvent, Never> { events.eraseToAnyPublisher() }
            func refresh() async {}
            func setVolume(_ value: Float) {}
            func setCurrentOutput(id: String) {}
        }
        var clock = t0
        let fake = Fake()
        let source = AudioActivitySource(provider: fake, now: { clock })
        var got: [IslandTransient] = []
        let c = source.transientsPublisher.sink { got.append($0) }

        // Initial load: placeholder volume, then real outputs and volume. Nothing emitted.
        fake.outputs.send([out("1", current: true), out("2")])
        fake.volume.send(0.4)
        XCTAssertTrue(got.isEmpty)

        clock = t0.addingTimeInterval(10)
        fake.volume.send(0.5)
        XCTAssertEqual(got.map(\.id), ["audio.volume"])

        fake.outputs.send([out("1"), out("2", current: true)])
        XCTAssertEqual(got.last?.id, "audio.output")
        clock = t0.addingTimeInterval(10.2)
        fake.volume.send(0.9)   // within 0.5s of the switch
        XCTAssertEqual(got.count, 2)

        clock = t0.addingTimeInterval(12)
        fake.outputs.send([out("1"), out("2", current: true), out("3", bt: true)])
        XCTAssertEqual(got.last?.id, "bluetooth.3")
        withExtendedLifetime(c) {}
    }
}
#endif

#if canImport(XCTest)
import Combine
import XCTest
@testable import MeloDock

@MainActor
private final class StubSource: ActivitySource {
    let subject = PassthroughSubject<[IslandActivity], Never>()
    let transients = PassthroughSubject<IslandTransient, Never>()
    var activitiesPublisher: AnyPublisher<[IslandActivity], Never> { subject.eraseToAnyPublisher() }
    var transientsPublisher: AnyPublisher<IslandTransient, Never> { transients.eraseToAnyPublisher() }
}

private final class FakeAudio: AudioDeviceProvider {
    let outputs = CurrentValueSubject<[AudioOutput], Never>([])
    let volume = CurrentValueSubject<Float, Never>(0.5)
    var outputsPublisher: AnyPublisher<[AudioOutput], Never> { outputs.eraseToAnyPublisher() }
    var volumePublisher: AnyPublisher<Float, Never> { volume.eraseToAnyPublisher() }
    func refresh() async {}
    func setVolume(_ value: Float) { volume.send(value) }
    func setCurrentOutput(id: String) {}
}

final class IslandKindFilterTests: XCTestCase {
    func testAllOnEnablesEveryKind() {
        XCTAssertEqual(IslandKindFilter.enabledKinds(showPower: true, showAudio: true, showCapture: true, showTimer: true, showCalendar: true),
                       IslandKindFilter.all)
    }

    func testEachSwitchGatesOnlyItsKind() {
        let noPower = IslandKindFilter.enabledKinds(showPower: false, showAudio: true, showCapture: true, showTimer: true, showCalendar: true)
        XCTAssertFalse(noPower.contains(.power))
        XCTAssertTrue(noPower.contains(.audio) && noPower.contains(.capture) && noPower.contains(.nowPlaying))

        let noAudio = IslandKindFilter.enabledKinds(showPower: true, showAudio: false, showCapture: true, showTimer: true, showCalendar: true)
        XCTAssertFalse(noAudio.contains(.audio))
        XCTAssertTrue(noAudio.contains(.power))

        let noCapture = IslandKindFilter.enabledKinds(showPower: true, showAudio: true, showCapture: false, showTimer: true, showCalendar: true)
        XCTAssertFalse(noCapture.contains(.capture))
        XCTAssertTrue(noCapture.contains(.timer) && noCapture.contains(.calendar))
    }

    func testTimerAndCalendarSwitchesGateTheirKinds() {
        let noTimer = IslandKindFilter.enabledKinds(showPower: true, showAudio: true, showCapture: true,
                                                    showTimer: false, showCalendar: true)
        XCTAssertFalse(noTimer.contains(.timer))
        XCTAssertTrue(noTimer.contains(.calendar) && noTimer.contains(.power))
        let noCalendar = IslandKindFilter.enabledKinds(showPower: true, showAudio: true, showCapture: true,
                                                       showTimer: true, showCalendar: false)
        XCTAssertFalse(noCalendar.contains(.calendar))
        XCTAssertTrue(noCalendar.contains(.timer) && noCalendar.contains(.nowPlaying))
    }

    func testNetworkSwitchGatesItsKindAndDefaultsOn() {
        let noNetwork = IslandKindFilter.enabledKinds(showPower: true, showAudio: true, showCapture: true,
                                                      showTimer: true, showCalendar: true, showNetwork: false)
        XCTAssertEqual(noNetwork, IslandKindFilter.all.subtracting([.network]))
        let defaulted = IslandKindFilter.enabledKinds(showPower: true, showAudio: true, showCapture: true,
                                                      showTimer: true, showCalendar: true)
        XCTAssertTrue(defaulted.contains(.network))
    }

    func testTransientQueueRemoveKind() {
        let t0 = Date(timeIntervalSinceReferenceDate: 100)
        func item(_ id: String, _ kind: IslandActivity.Kind) -> IslandTransient {
            IslandTransient(id: id, kind: kind, payload: .volume(0.5), duration: 3, sticky: false)
        }
        var q = TransientQueue()
        q.enqueue(item("a", .audio), now: t0)
        q.enqueue(item("p", .power), now: t0)
        q.enqueue(item("b", .audio), now: t0)
        q.remove(kind: .audio, now: t0.addingTimeInterval(1))
        XCTAssertEqual(q.current?.id, "p")
        XCTAssertTrue(q.pending.isEmpty)
        XCTAssertEqual(q.expiresAt, t0.addingTimeInterval(4))
        q.remove(kind: .power, now: t0.addingTimeInterval(2))
        XCTAssertNil(q.current)
        XCTAssertNil(q.expiresAt)
    }

    @MainActor
    func testSettingsPublisherReflectsSwitches() {
        let suite = "IslandWiringTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults)
        var latest: Set<IslandActivity.Kind>?
        let c = store.enabledKindsPublisher.sink { latest = $0 }
        XCTAssertEqual(latest, IslandKindFilter.all.subtracting([.calendar]))
        store.showAudio = false
        XCTAssertEqual(latest?.contains(.audio), false)
        store.showAudio = true
        store.showCapture = false
        XCTAssertEqual(latest?.contains(.capture), false)
        XCTAssertEqual(latest?.contains(.audio), true)
        store.showTimer = false
        XCTAssertEqual(latest?.contains(.timer), false)
        store.showCalendar = true
        XCTAssertEqual(latest?.contains(.calendar), true)
        c.cancel()
    }
}

@MainActor
final class IslandWiringTests: XCTestCase {
    private func transient(_ id: String, _ kind: IslandActivity.Kind) -> IslandTransient {
        IslandTransient(id: id, kind: kind, payload: .volume(0.5), duration: 60, sticky: false)
    }

    private let playing = IslandActivity(id: "nowPlaying", kind: .nowPlaying, priority: 60)
    private let capture = IslandActivity(id: "capture", kind: .capture, priority: 40,
                                         detail: .capture(mic: true, camera: false))

    func testDisablingCaptureRemovesItFromSelectionAndReenablingRestoresIt() {
        let s = StubSource()
        let c = IslandCoordinator(sources: [s])
        s.subject.send([capture, playing])
        XCTAssertEqual(c.selection.secondary?.id, "capture")
        c.enabledKinds = IslandKindFilter.enabledKinds(showPower: true, showAudio: true, showCapture: false, showTimer: true, showCalendar: true)
        XCTAssertNil(c.selection.secondary)
        XCTAssertEqual(c.selection.primary?.id, "nowPlaying")
        c.enabledKinds = IslandKindFilter.all
        XCTAssertEqual(c.selection.secondary?.id, "capture")
    }

    func testCaptureOnlyDisabledLeavesIdle() {
        let s = StubSource()
        let c = IslandCoordinator(sources: [s])
        s.subject.send([capture])
        XCTAssertEqual(c.mode, .compact)
        c.enabledKinds = IslandKindFilter.enabledKinds(showPower: true, showAudio: true, showCapture: false, showTimer: true, showCalendar: true)
        XCTAssertEqual(c.mode, .idle)
    }

    func testDisabledKindTransientsAreDropped() {
        let s = StubSource()
        let c = IslandCoordinator(sources: [s])
        c.enabledKinds = IslandKindFilter.enabledKinds(showPower: false, showAudio: false, showCapture: true, showTimer: true, showCalendar: true)
        s.transients.send(transient("p", .power))
        s.transients.send(transient("a", .audio))
        XCTAssertNil(c.transient)
        c.enabledKinds = IslandKindFilter.all
        s.transients.send(transient("a", .audio))
        XCTAssertEqual(c.transient?.id, "a")
    }

    func testDisablingKindClearsItsShownAndPendingTransients() {
        let s = StubSource()
        let c = IslandCoordinator(sources: [s])
        s.transients.send(transient("a", .audio))
        s.transients.send(transient("p", .power))
        XCTAssertEqual(c.transient?.id, "a")
        c.enabledKinds = IslandKindFilter.enabledKinds(showPower: true, showAudio: false, showCapture: true, showTimer: true, showCalendar: true)
        XCTAssertEqual(c.transient?.id, "p")
        c.enabledKinds = IslandKindFilter.enabledKinds(showPower: false, showAudio: false, showCapture: true, showTimer: true, showCalendar: true)
        XCTAssertNil(c.transient)
    }

    /// The island's own volume slider drives `setVolume`, which echoes through `volumePublisher`.
    func testDraggingTheExpandedVolumeSliderDoesNotPopATransient() {
        let audio = FakeAudio()
        let source = AudioActivitySource(provider: audio)
        let c = IslandCoordinator(sources: [source])
        audio.outputs.send([AudioOutput(id: "1", name: "Speakers", isCurrent: true)])
        audio.volume.send(0.4)
        XCTAssertNil(c.transient)

        c.expand()
        for step in stride(from: 0.45 as Float, through: 0.9, by: 0.05) { audio.setVolume(step) }
        XCTAssertNil(c.transient)
        XCTAssertEqual(c.mode, .expanded)

        c.toggleExpanded()
        XCTAssertNil(c.transient, "nothing was deferred while expanded")

        // Control: a hardware volume change while collapsed does show the transient.
        audio.setVolume(0.2)
        XCTAssertEqual(c.transient?.id, AudioEventMapper.volumeID)
    }
}
#endif

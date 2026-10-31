import AppKit
import AudioToolbox
import Combine
import CoreAudio
import Foundation

/// What a tap listens to.
enum SpectrumTapTarget: Equatable {
    /// One app's audio, found by bundle id.
    case process(bundleID: String)
    /// Everything the Mac plays except MeloDock itself.
    case global

    /// Music app first (only its sound reaches the bars), then the whole system in case that app renders its
    /// audio in a helper process the tap cannot see.
    static func attempts(for provider: MusicProviderKind) -> [SpectrumTapTarget] {
        [.process(bundleID: provider.bundleID), .global]
    }
}

extension MusicProviderKind {
    var bundleID: String {
        switch self {
        case .appleMusic: "com.apple.Music"
        case .spotify: "com.spotify.client"
        }
    }
}

private protocol TapSessionControlling: AnyObject {
    func stop()
}

/// Feeds the island real audio levels from a Core Audio process tap (macOS 14.2+). It listens only while the
/// switch is on and music is playing, and falls back to nothing (so the view animates synthetically) when no
/// sound arrives, which is how a missing System Audio Recording permission shows up.
@MainActor
final class CoreAudioTapSpectrumService: SpectrumSource {
    private struct Desired: Equatable {
        var active: Bool
        var provider: MusicProviderKind
    }

    private let levelsSubject = CurrentValueSubject<[Float]?, Never>(nil)
    private let statusSubject = CurrentValueSubject<SpectrumStatus, Never>(.off)
    private var cancellable: AnyCancellable?
    private var session: TapSessionControlling?
    private var monitor = TapSilenceMonitor(startedAt: .distantPast)
    private var generation = 0

    var levelsPublisher: AnyPublisher<[Float]?, Never> { levelsSubject.removeDuplicates().eraseToAnyPublisher() }
    var statusPublisher: AnyPublisher<SpectrumStatus, Never> { statusSubject.removeDuplicates().eraseToAnyPublisher() }

    init(isEnabled: AnyPublisher<Bool, Never>, isPlaying: AnyPublisher<Bool, Never>,
         provider: AnyPublisher<MusicProviderKind, Never>) {
        cancellable = Publishers.CombineLatest3(isEnabled, isPlaying, provider)
            .map { Desired(active: $0 && $1, provider: $2) }
            .removeDuplicates()
            .sink { [weak self] desired in self?.apply(desired) }
    }

    private func apply(_ desired: Desired) {
        stopSession()
        guard desired.active else {
            statusSubject.send(.off)
            return
        }
        guard #available(macOS 14.2, *) else {
            statusSubject.send(.unsupported)
            return
        }
        statusSubject.send(.waiting)
        run(SpectrumTapTarget.attempts(for: desired.provider), at: 0, generation: generation)
    }

    @available(macOS 14.2, *)
    private func run(_ targets: [SpectrumTapTarget], at index: Int, generation: Int) {
        guard generation == self.generation else { return }
        guard index < targets.count else {
            statusSubject.send(.denied)
            return
        }
        monitor = TapSilenceMonitor(startedAt: Date())
        let started = TapSession(target: targets[index]) { [weak self] levels, rms in
            MainActor.assumeIsolated {
                self?.receive(levels: levels, rms: rms, generation: generation, targets: targets, index: index)
            }
        }
        guard let started else {
            run(targets, at: index + 1, generation: generation)
            return
        }
        session = started
    }

    @available(macOS 14.2, *)
    private func receive(levels: [Float], rms: Float, generation: Int, targets: [SpectrumTapTarget], index: Int) {
        guard generation == self.generation else { return }
        monitor.record(rms: rms)
        switch monitor.verdict(at: Date()) {
        case .heardAudio:
            statusSubject.send(.live)
            levelsSubject.send(levels)
        case .waiting:
            break
        case .silent:
            // This target is deaf: drop it and try the next one.
            session?.stop()
            session = nil
            run(targets, at: index + 1, generation: generation)
        }
    }

    private func stopSession() {
        generation += 1
        session?.stop()
        session = nil
        levelsSubject.send(nil)
    }
}

/// One tap + aggregate device + IO proc. All audio work stays on its own serial queue; results go to the main queue.
@available(macOS 14.2, *)
private final class TapSession: TapSessionControlling {
    private static let bandCount = 14
    private static let emitInterval: TimeInterval = 1.0 / 30
    private static let windowSize = SpectrumAnalyzer.fftSize * 2

    private let queue = DispatchQueue(label: "melodock.spectrum.tap", qos: .userInteractive)
    private let onFrame: @Sendable ([Float], Float) -> Void
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var isStopped = false

    // Touched only on `queue`.
    private var analyzer: SpectrumAnalyzer?
    private var smoother = SpectrumSmoother(bandCount: TapSession.bandCount)
    private var window: [Float] = []
    private var peakSinceEmit: Float = 0
    private var lastEmit = Date.distantPast

    /// Nil when any step of the setup fails.
    init?(target: SpectrumTapTarget, onFrame: @escaping @Sendable ([Float], Float) -> Void) {
        self.onFrame = onFrame
        guard let description = Self.description(for: target) else { return nil }
        description.uuid = UUID()
        description.name = "MeloDock spectrum"
        description.isPrivate = true
        description.muteBehavior = .unmuted

        guard AudioHardwareCreateProcessTap(description, &tapID) == noErr,
              let outputUID = CoreAudioProperty.defaultOutputDeviceUID() else {
            teardown()
            return nil
        }
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "MeloDock spectrum",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true,
                                               kAudioSubTapUIDKey: description.uuid.uuidString]]
        ]
        guard AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID) == noErr else {
            teardown()
            return nil
        }
        let sampleRate = CoreAudioProperty.nominalSampleRate(aggregateID) ?? 48_000
        analyzer = SpectrumAnalyzer(bandCount: Self.bandCount, sampleRate: sampleRate)
        guard analyzer != nil,
              AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue, { [weak self] _, input, _, _, _ in
                  self?.handle(input)
              }) == noErr, procID != nil,
              AudioDeviceStart(aggregateID, procID) == noErr else {
            teardown()
            return nil
        }
    }

    deinit { teardown() }

    func stop() {
        // After this returns no frame is delivered: `handle` checks the flag on the same queue.
        queue.sync { isStopped = true }
        teardown()
    }

    private func teardown() {
        if aggregateID != kAudioObjectUnknown, let procID {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
        }
        procID = nil
        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    private func handle(_ input: UnsafePointer<AudioBufferList>) {
        guard !isStopped, let analyzer else { return }
        let list = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let blocks: [AudioBlock] = list.compactMap { buffer in
            guard let data = buffer.mData, buffer.mNumberChannels > 0 else { return nil }
            let channels = Int(buffer.mNumberChannels)
            return AudioBlock(samples: UnsafePointer(data.assumingMemoryBound(to: Float.self)), channels: channels,
                              frames: Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * channels))
        }
        let mono = MonoMixer.mix(blocks)
        guard !mono.isEmpty else { return }
        peakSinceEmit = max(peakSinceEmit, MonoMixer.rms(mono))
        window.append(contentsOf: mono)
        if window.count > Self.windowSize { window.removeFirst(window.count - Self.windowSize) }

        let now = Date()
        guard now.timeIntervalSince(lastEmit) >= Self.emitInterval else { return }
        lastEmit = now
        let levels = smoother.update(analyzer.levels(for: window))
        let rms = peakSinceEmit
        peakSinceEmit = 0
        let deliver = onFrame
        DispatchQueue.main.async { deliver(levels, rms) }
    }

    private static func description(for target: SpectrumTapTarget) -> CATapDescription? {
        switch target {
        case .global:
            let own = CoreAudioProperty.processObject(pid: getpid())
            return CATapDescription(stereoGlobalTapButExcludeProcesses: own.map { [$0] } ?? [])
        case let .process(bundleID):
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
                  let object = CoreAudioProperty.processObject(pid: app.processIdentifier) else { return nil }
            return CATapDescription(stereoMixdownOfProcesses: [object])
        }
    }
}

private enum CoreAudioProperty {
    private static let system = AudioObjectID(kAudioObjectSystemObject)

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    static func processObject(pid: pid_t) -> AudioObjectID? {
        var pid = pid
        var object = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var property = address(kAudioHardwarePropertyTranslatePIDToProcessObject)
        let status = AudioObjectGetPropertyData(system, &property, UInt32(MemoryLayout<pid_t>.size), &pid, &size, &object)
        return status == noErr && object != kAudioObjectUnknown ? object : nil
    }

    static func defaultOutputDeviceUID() -> String? {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var property = address(kAudioHardwarePropertyDefaultSystemOutputDevice)
        guard AudioObjectGetPropertyData(system, &property, 0, nil, &size, &device) == noErr else { return nil }
        var uid: Unmanaged<CFString>?
        var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var uidProperty = address(kAudioDevicePropertyDeviceUID)
        guard AudioObjectGetPropertyData(device, &uidProperty, 0, nil, &uidSize, &uid) == noErr else { return nil }
        return uid?.takeRetainedValue() as String?
    }

    static func nominalSampleRate(_ device: AudioObjectID) -> Double? {
        var rate: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        var property = address(kAudioDevicePropertyNominalSampleRate)
        return AudioObjectGetPropertyData(device, &property, 0, nil, &size, &rate) == noErr && rate > 0 ? rate : nil
    }
}

import Combine
import Foundation

/// Pure mapping from audio device/volume changes to island transients.
enum AudioEventMapper {
    static let volumeID = "audio.volume"
    static let outputID = "audio.output"
    static let outputSwitchVolumeSuppression: TimeInterval = 0.5
    static let volumeEpsilon: Float = 0.001

    static func bluetoothID(_ deviceID: String) -> String { "bluetooth.\(deviceID)" }

    /// - Parameters:
    ///   - old: previous outputs, nil for the initial load (nothing is emitted).
    ///   - oldVolume: previous volume, nil until a baseline exists.
    ///   - newVolume: nil when this update carries no volume reading.
    ///   - lastOutputSwitchAt: when the last `.output` transient was produced.
    static func transients(old: [AudioOutput]?, new: [AudioOutput], oldVolume: Float?, newVolume: Float?,
                           now: Date, lastOutputSwitchAt: Date?) -> [IslandTransient] {
        guard let old else { return [] }
        var result: [IslandTransient] = []

        let oldIDs = Set(old.map(\.id))
        let newIDs = Set(new.map(\.id))
        for device in new where device.isBluetooth && !oldIDs.contains(device.id) {
            result.append(IslandTransient(id: bluetoothID(device.id), kind: .audio,
                                          payload: .bluetooth(name: device.name, connected: true),
                                          duration: 3, sticky: false))
        }
        for device in old where device.isBluetooth && !newIDs.contains(device.id) {
            result.append(IslandTransient(id: bluetoothID(device.id), kind: .audio,
                                          payload: .bluetooth(name: device.name, connected: false),
                                          duration: 3, sticky: false))
        }

        var outputChanged = false
        let oldCurrent = old.first(where: \.isCurrent)
        if let newCurrent = new.first(where: \.isCurrent), newCurrent.id != oldCurrent?.id {
            outputChanged = true
            result.append(IslandTransient(id: outputID, kind: .audio, payload: .output(name: newCurrent.name),
                                          duration: 3, sticky: false))
        }

        if let oldVolume, let newVolume, abs(newVolume - oldVolume) > volumeEpsilon, !outputChanged {
            let recentSwitch = lastOutputSwitchAt.map { now.timeIntervalSince($0) < outputSwitchVolumeSuppression } ?? false
            if !recentSwitch {
                result.append(IslandTransient(id: volumeID, kind: .audio, payload: .volume(newVolume),
                                              duration: 1.5, sticky: true))
            }
        }
        return result
    }
}

/// Emits bluetooth / output-switch / volume transients from an `AudioDeviceProvider`.
/// It consumes the provider's outputs and volume publishers (kept fresh by whoever calls `refresh()` on
/// `eventsPublisher`, i.e. `IslandViewModel`) and contributes no long-lived activities.
@MainActor
final class AudioActivitySource: ActivitySource {
    private let transientSubject = PassthroughSubject<IslandTransient, Never>()
    private let now: () -> Date
    private var outputs: [AudioOutput]?
    private var volume: Float?
    private var lastOutputSwitchAt: Date?
    private var cancellables = Set<AnyCancellable>()

    var activitiesPublisher: AnyPublisher<[IslandActivity], Never> {
        Empty(completeImmediately: false).eraseToAnyPublisher()
    }

    var transientsPublisher: AnyPublisher<IslandTransient, Never> {
        transientSubject.eraseToAnyPublisher()
    }

    init(provider: AudioDeviceProvider, now: @escaping () -> Date = Date.init) {
        self.now = now
        provider.outputsPublisher.sink { [weak self] value in
            MainActor.assumeIsolated { self?.receive(outputs: value) }
        }.store(in: &cancellables)
        provider.volumePublisher.sink { [weak self] value in
            MainActor.assumeIsolated { self?.receive(volume: value) }
        }.store(in: &cancellables)
    }

    private func receive(outputs new: [AudioOutput]) {
        // Placeholder emission before the first real device list: not a baseline.
        guard outputs != nil || !new.isEmpty else { return }
        emit(AudioEventMapper.transients(old: outputs, new: new, oldVolume: nil, newVolume: nil,
                                         now: now(), lastOutputSwitchAt: lastOutputSwitchAt))
        outputs = new
    }

    private func receive(volume new: Float) {
        // Volume seen before the device list is the provider's placeholder.
        guard let outputs else { return }
        emit(AudioEventMapper.transients(old: outputs, new: outputs, oldVolume: volume, newVolume: new,
                                         now: now(), lastOutputSwitchAt: lastOutputSwitchAt))
        volume = new
    }

    private func emit(_ items: [IslandTransient]) {
        for item in items {
            if item.id == AudioEventMapper.outputID { lastOutputSwitchAt = now() }
            transientSubject.send(item)
        }
    }
}

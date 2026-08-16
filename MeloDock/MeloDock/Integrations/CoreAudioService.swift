import AudioToolbox
import Combine
import CoreAudio
import Foundation

final class CoreAudioService: AudioDeviceProvider, @unchecked Sendable {
    private let outputsSubject = CurrentValueSubject<[AudioOutput], Never>([])
    private let volumeSubject = CurrentValueSubject<Float, Never>(0.5)
    private let queue = DispatchQueue(label: "com.nano.melodock.coreaudio", qos: .utility)

    var outputsPublisher: AnyPublisher<[AudioOutput], Never> {
        outputsSubject
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }

    var volumePublisher: AnyPublisher<Float, Never> {
        volumeSubject
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }

    func refresh() async {
        let snapshot: ([AudioOutput], Float) = await withCheckedContinuation { continuation in
            queue.async {
                let outputs = self.fetchOutputs()
                let volume = self.fetchCurrentVolume()
                continuation.resume(returning: (outputs, volume))
            }
        }

        outputsSubject.send(snapshot.0)
        volumeSubject.send(snapshot.1)
    }

    func setVolume(_ value: Float) {
        let clamped = max(0, min(1, value))

        queue.async {
            guard let deviceID = self.defaultOutputDeviceID() else { return }

            var preferredAddress = AudioObjectPropertyAddress(
                mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )

            var scalar = Float32(clamped)
            let size = UInt32(MemoryLayout<Float32>.size)

            if AudioObjectHasProperty(deviceID, &preferredAddress) {
                _ = AudioObjectSetPropertyData(deviceID, &preferredAddress, 0, nil, size, &scalar)
            } else {
                self.setChannelVolume(deviceID: deviceID, channel: 1, value: scalar)
                self.setChannelVolume(deviceID: deviceID, channel: 2, value: scalar)
            }

            let refreshed = self.fetchCurrentVolume()
            DispatchQueue.main.async {
                self.volumeSubject.send(refreshed)
            }
        }
    }

    func setCurrentOutput(id: String) {
        guard let rawValue = UInt32(id) else { return }
        var deviceID = AudioDeviceID(rawValue)

        queue.async {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )

            let size = UInt32(MemoryLayout<AudioDeviceID>.size)
            let status = AudioObjectSetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                0,
                nil,
                size,
                &deviceID
            )

            if status == noErr {
                let outputs = self.fetchOutputs()
                DispatchQueue.main.async {
                    self.outputsSubject.send(outputs)
                }
            }
        }
    }

    private func fetchOutputs() -> [AudioOutput] {
        let systemObject = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(systemObject, &address, 0, nil, &size) == noErr else { return [] }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = Array(repeating: AudioDeviceID(), count: count)
        guard AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &deviceIDs) == noErr else { return [] }

        let current = defaultOutputDeviceID()

        return deviceIDs.compactMap { deviceID in
            guard deviceHasOutput(deviceID) else { return nil }
            return AudioOutput(
                id: String(deviceID),
                name: deviceName(for: deviceID),
                isCurrent: deviceID == current
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func fetchCurrentVolume() -> Float {
        guard let deviceID = defaultOutputDeviceID() else { return 0.5 }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        var volume = Float32(0.5)
        var size = UInt32(MemoryLayout<Float32>.size)

        if AudioObjectHasProperty(deviceID, &address),
           AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume) == noErr {
            return max(0, min(1, Float(volume)))
        }

        var leftAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: 1
        )

        if AudioObjectHasProperty(deviceID, &leftAddress),
           AudioObjectGetPropertyData(deviceID, &leftAddress, 0, nil, &size, &volume) == noErr {
            return max(0, min(1, Float(volume)))
        }

        return 0.5
    }

    private func defaultOutputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID = AudioDeviceID()
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)

        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        ) == noErr else {
            return nil
        }

        return deviceID
    }

    private func deviceHasOutput(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr && size > 0
    }

    private func deviceName(for deviceID: AudioDeviceID) -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<CFString?>.size)

        if AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &name) == noErr,
           let name {
            return name.takeRetainedValue() as String
        }

        return "Output \(deviceID)"
    }

    private func setChannelVolume(deviceID: AudioDeviceID, channel: UInt32, value: Float32) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: channel
        )

        var mutableValue = value
        let size = UInt32(MemoryLayout<Float32>.size)

        if AudioObjectHasProperty(deviceID, &address) {
            _ = AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &mutableValue)
        }
    }
}

import Combine
import CoreAudio
import CoreMediaIO
import Foundation

/// Watches whether any process is running an input audio device (microphone) or, optionally, a camera.
///
/// Camera detection is off by default (`supportsCamera == false`): whether
/// `kCMIODevicePropertyDeviceIsRunningSomewhere` is readable in the sandbox without the camera entitlement
/// is unverified and needs a hardware spike.
@MainActor
final class CaptureActivityService {
    private let supportsCamera: Bool
    private let subject: CurrentValueSubject<CaptureUsage, Never>
    private let audioListeners = CoreAudioListenerBag()
    private static let deviceTag = "inputDevice"
    private var cameraRegistrations: [(CMIOObjectID, CMIOObjectPropertyAddress)] = []
    private var cameraBlock: CMIOObjectPropertyListenerBlock?
    private var cameraListListenerRegistered = false

    var usagePublisher: AnyPublisher<CaptureUsage, Never> {
        subject.eraseToAnyPublisher()
    }

    init(supportsCamera: Bool = false) {
        self.supportsCamera = supportsCamera
        subject = CurrentValueSubject(CaptureUsage(mic: false, camera: false))
        registerAudioListeners()
        if supportsCamera { registerCameraListeners() }
        refresh()
    }

    deinit {
        audioListeners.removeAll()
        removeCameraListeners()
    }

    private func refresh() {
        let usage = CaptureUsage(mic: Self.isAnyInputRunning(),
                                 camera: supportsCamera ? Self.isAnyCameraRunning() : false)
        if usage != subject.value { subject.send(usage) }
    }

    // MARK: Microphone

    private func registerAudioListeners() {
        audioListeners.add(objectID: AudioObjectID(kAudioObjectSystemObject),
                           selector: kAudioHardwarePropertyDevices) { [weak self] in
            MainActor.assumeIsolated {
                self?.registerInputDeviceListeners()
                self?.refresh()
            }
        }
        registerInputDeviceListeners()
    }

    private func registerInputDeviceListeners() {
        audioListeners.remove(tag: Self.deviceTag)
        for device in Self.inputDeviceIDs() {
            audioListeners.add(objectID: device, selector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                               tag: Self.deviceTag) { [weak self] in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
    }

    private nonisolated static func audioDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var ids = Array(repeating: AudioDeviceID(), count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private nonisolated static func inputDeviceIDs() -> [AudioDeviceID] {
        audioDeviceIDs().filter { device in
            var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                                     mScope: kAudioDevicePropertyScopeInput,
                                                     mElement: kAudioObjectPropertyElementMain)
            var size: UInt32 = 0
            return AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr && size > 0
        }
    }

    private nonisolated static func isAnyInputRunning() -> Bool {
        inputDeviceIDs().contains { device in
            var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                                                     mScope: kAudioObjectPropertyScopeGlobal,
                                                     mElement: kAudioObjectPropertyElementMain)
            var running: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running) == noErr && running != 0
        }
    }

    // MARK: Camera (CoreMediaIO)

    private nonisolated static func cameraDeviceIDs() -> [CMIOObjectID] {
        var address = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
                                                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var size: UInt32 = 0
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        guard CMIOObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var ids = Array(repeating: CMIOObjectID(), count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &address, 0, nil, size, &used, &ids) == noErr else { return [] }
        return ids
    }

    private nonisolated static func runningSomewhereAddress() -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                                  mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                  mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
    }

    private nonisolated static func isAnyCameraRunning() -> Bool {
        cameraDeviceIDs().contains { device in
            var address = runningSomewhereAddress()
            var running: UInt32 = 0
            var used: UInt32 = 0
            return CMIOObjectGetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &used, &running) == noErr
                && running != 0
        }
    }

    private func registerCameraListeners() {
        let block: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.registerCameraListeners()
                self?.refresh()
            }
        }
        removeCameraListeners()
        cameraBlock = block
        var listAddress = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
                                                    mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                                    mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        if CMIOObjectAddPropertyListenerBlock(system, &listAddress, .main, block) == noErr {
            cameraRegistrations.append((system, listAddress))
        }
        for device in Self.cameraDeviceIDs() {
            var address = Self.runningSomewhereAddress()
            if CMIOObjectAddPropertyListenerBlock(device, &address, .main, block) == noErr {
                cameraRegistrations.append((device, address))
            }
        }
    }

    private nonisolated func removeCameraListeners() {
        // Called from deinit; registrations are only mutated on the main actor before deinit.
        MainActor.assumeIsolated {
            guard let block = cameraBlock else { return }
            for (object, address) in cameraRegistrations {
                var address = address
                CMIOObjectRemovePropertyListenerBlock(object, &address, .main, block)
            }
            cameraRegistrations.removeAll()
        }
    }
}

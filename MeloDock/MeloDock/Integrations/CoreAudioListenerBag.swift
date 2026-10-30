import CoreAudio
import Foundation

/// Owns CoreAudio property listener blocks and removes every one of them on `removeAll()` / deinit.
/// Handlers are delivered on `queue` (main by default). Not thread-safe: mutate from the main thread.
final class CoreAudioListenerBag {
    private struct Entry {
        let objectID: AudioObjectID
        var address: AudioObjectPropertyAddress
        let queue: DispatchQueue
        let block: AudioObjectPropertyListenerBlock
        let tag: String
    }

    private var entries: [Entry] = []

    init() {}

    deinit { removeAll() }

    /// Registers a listener. `tag` lets callers drop a group later (e.g. per-device listeners).
    @discardableResult
    func add(objectID: AudioObjectID,
             selector: AudioObjectPropertySelector,
             scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
             element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain,
             tag: String = "",
             queue: DispatchQueue = .main,
             handler: @escaping () -> Void) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
        let block: AudioObjectPropertyListenerBlock = { _, _ in handler() }
        let status = AudioObjectAddPropertyListenerBlock(objectID, &address, queue, block)
        guard status == noErr else { return false }
        entries.append(Entry(objectID: objectID, address: address, queue: queue, block: block, tag: tag))
        return true
    }

    func remove(tag: String) {
        entries.removeAll { entry in
            guard entry.tag == tag else { return false }
            var address = entry.address
            AudioObjectRemovePropertyListenerBlock(entry.objectID, &address, entry.queue, entry.block)
            return true
        }
    }

    func removeAll() {
        for entry in entries {
            var address = entry.address
            AudioObjectRemovePropertyListenerBlock(entry.objectID, &address, entry.queue, entry.block)
        }
        entries.removeAll()
    }
}

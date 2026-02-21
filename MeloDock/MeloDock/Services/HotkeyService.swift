import Carbon
import Foundation

struct HotkeyConfiguration: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    static let `default` = HotkeyConfiguration(
        keyCode: 46,
        modifiers: UInt32(cmdKey | optionKey)
    )

    var displayName: String {
        let values: [(UInt32, String)] = [
            (UInt32(cmdKey), "Command"),
            (UInt32(optionKey), "Option"),
            (UInt32(controlKey), "Control"),
            (UInt32(shiftKey), "Shift")
        ]

        let active = values.compactMap { flag, label in
            (modifiers & flag) != 0 ? label : nil
        }

        return (active + [keyCodeName]).joined(separator: "+")
    }

    private var keyCodeName: String {
        switch keyCode {
        case 46:
            return "M"
        case 49:
            return "Space"
        default:
            return "KeyCode(\(keyCode))"
        }
    }
}

final class HotkeyService {
    var onHotkeyPressed: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let hotKeyID = EventHotKeyID(signature: OSType(0x4D454C4F), id: 1)

    init() {
        Self.shared = self
        installHandler()
    }

    deinit {
        unregister()
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
        }
    }

    func register(hotkey: HotkeyConfiguration) {
        unregister()

        let mutableHotKeyID = hotKeyID
        let status = RegisterEventHotKey(
            hotkey.keyCode,
            hotkey.modifiers,
            mutableHotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if status != noErr {
            print("Hotkey registration failed: \(status)")
        }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    private func installHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            Self.hotkeyHandlerUPP,
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )

        if status != noErr {
            print("Hotkey event handler install failed: \(status)")
        }
    }

    private static var shared: HotkeyService?

    private static let hotkeyHandlerUPP: EventHandlerUPP = { _, _, _ in
        DispatchQueue.main.async {
            shared?.onHotkeyPressed?()
        }
        return noErr
    }
}

import Cocoa
import Carbon

@MainActor
public final class HotKeyManager {
    public static let shared = HotKeyManager()

    public var onToggleActiveWindowPin: (() -> Void)?
    public var onStartWindowPicker: (() -> Void)?
    public var onToggleGhostMode: (() -> Void)?
    public var onUnpinAll: (() -> Void)?

    private var hotKeyRefs: [EventHotKeyRef] = []
    private var eventHandlerRef: EventHandlerRef?

    private init() {}

    public func registerGlobalHotKeys() {
        unregisterAll()

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let callback: EventHandlerUPP = { _, eventRef, _ -> OSStatus in
            guard let eventRef = eventRef else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                eventRef,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            if status == noErr {
                let id = hotKeyID.id
                DispatchQueue.main.async {
                    HotKeyManager.shared.handleHotKey(id: id)
                }
            }
            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )

        let modifiers = UInt32(controlKey | optionKey)
        registerKey(keyCode: UInt32(kVK_ANSI_P), modifiers: modifiers, id: 1) // ⌃⌥P: Pin Active Window
        registerKey(keyCode: UInt32(kVK_ANSI_K), modifiers: modifiers, id: 2) // ⌃⌥K: Crosshair Picker
        registerKey(keyCode: UInt32(kVK_ANSI_G), modifiers: modifiers, id: 3) // ⌃⌥G: Toggle Ghost Mode
        registerKey(keyCode: UInt32(kVK_ANSI_U), modifiers: modifiers, id: 4) // ⌃⌥U: Unpin All
    }

    private func registerKey(keyCode: UInt32, modifiers: UInt32, id: UInt32) {
        var ref: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: OSType(0x50544F50), id: id)
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hkID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr, let ref = ref {
            hotKeyRefs.append(ref)
        }
    }

    private func handleHotKey(id: UInt32) {
        switch id {
        case 1:
            onToggleActiveWindowPin?()
        case 2:
            onStartWindowPicker?()
        case 3:
            onToggleGhostMode?()
        case 4:
            onUnpinAll?()
        default:
            break
        }
    }

    public func unregisterAll() {
        for ref in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
            eventHandlerRef = nil
        }
    }
}

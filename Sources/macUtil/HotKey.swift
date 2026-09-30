import AppKit
import Carbon.HIToolbox

/// One system-wide hot key. Carbon is used deliberately: it is the only global
/// hot key API that does not require Accessibility permission.
@MainActor
final class HotKey {
    /// The C callback cannot capture context, so live instances are looked up by id.
    private static var instances: [UInt32: HotKey] = [:]
    private static var nextID: UInt32 = 1
    private static var handler: EventHandlerRef?

    private let id: UInt32
    private let action: @MainActor () -> Void
    private var reference: EventHotKeyRef?

    init(keyCode: UInt32, modifiers: UInt32, action: @escaping @MainActor () -> Void) {
        self.id = HotKey.nextID
        self.action = action
        HotKey.nextID += 1
        HotKey.instances[id] = self

        HotKey.installHandlerIfNeeded()

        // 'mUt1' — an arbitrary but stable signature for this app's hot keys.
        let hotKeyID = EventHotKeyID(signature: OSType(0x6D_55_74_31), id: id)
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &reference
        )
        NSLog("macUtil hot key registration status: %d", Int(status))
    }

    deinit {
        // Both `reference` and `instances` are main-actor-isolated state; `deinit`
        // cannot itself be isolated, but this class's lifetime is tied to the app's
        // main-thread lifecycle, so assuming isolation here is sound.
        MainActor.assumeIsolated {
            if let reference {
                UnregisterEventHotKey(reference)
            }
            HotKey.instances[id] = nil
        }
    }

    private static func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, _ -> OSStatus in
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr else { return status }
                // Carbon hot key events are delivered on the main thread.
                MainActor.assumeIsolated {
                    HotKey.instances[hotKeyID.id]?.action()
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            &handler
        )
    }
}

extension HotKey {
    /// Control + Option + V — the app's default trigger. Chosen over Cmd+Shift+V,
    /// which many apps already use for "Paste and Match Style".
    static func controlOptionV(action: @escaping @MainActor () -> Void) -> HotKey {
        HotKey(
            keyCode: UInt32(kVK_ANSI_V),
            modifiers: UInt32(controlKey | optionKey),
            action: action
        )
    }
}

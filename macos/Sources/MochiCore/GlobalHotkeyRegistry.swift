import Carbon.HIToolbox
import Foundation

/// Wraps Carbon's `RegisterEventHotKey` — still the standard way to claim a system-wide hotkey on
/// macOS without needing Accessibility permission (unlike the `CGEventPostToPid` key *injection*
/// used by Hotkey Forwarding, ADR-0003, which is a separate concern). A singleton because Carbon's
/// event handler is a single C callback shared process-wide, dispatching by the numeric hotkey ID
/// it was registered under.
final class GlobalHotkeyRegistry {
    static let shared = GlobalHotkeyRegistry()

    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var ids: [Hotkey: UInt32] = [:]
    private var nextHotkeyID: UInt32 = 1
    private var eventHandlerRef: EventHandlerRef?
    private static let signature: OSType = 0x4d6f4368  // 'MoCh'

    private init() {}

    @discardableResult
    func register(_ hotkey: Hotkey, perform handler: @escaping () -> Void) -> Bool {
        installEventHandlerIfNeeded()

        let hotkeyID = nextHotkeyID
        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            hotkey.keyCode,
            hotkey.modifierFlags,
            EventHotKeyID(signature: Self.signature, id: hotkeyID),
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard status == noErr, let hotKeyRef else { return false }

        handlers[hotkeyID] = handler
        refs[hotkeyID] = hotKeyRef
        ids[hotkey] = hotkeyID
        nextHotkeyID += 1
        return true
    }

    /// Hands `hotkey`'s combination back to the system so another app (or a later re-registration
    /// of the same combo) can claim it. A safe no-op when `hotkey` was never registered — callers
    /// don't need to track registration success themselves before unregistering.
    func unregister(_ hotkey: Hotkey) {
        guard let hotkeyID = ids.removeValue(forKey: hotkey) else { return }
        if let ref = refs.removeValue(forKey: hotkeyID) {
            UnregisterEventHotKey(ref)
        }
        handlers.removeValue(forKey: hotkeyID)
    }

    /// Test-only: fires the handler currently registered for `hotkey` as if its Carbon event had
    /// arrived, without synthesizing a real key event (which a headless test process cannot do).
    /// `internal` rather than `private` so `@testable import` can reach it.
    func simulateHotkeyPressed(_ hotkey: Hotkey) {
        guard let hotkeyID = ids[hotkey] else { return }
        handlers[hotkeyID]?()
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let userData = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, eventRef, userData in
                guard let eventRef, let userData else { return OSStatus(eventNotHandledErr) }
                var hotkeyID = EventHotKeyID()
                let status = GetEventParameter(
                    eventRef, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                    nil, MemoryLayout<EventHotKeyID>.size, nil, &hotkeyID
                )
                guard status == noErr else { return status }
                Unmanaged<GlobalHotkeyRegistry>.fromOpaque(userData).takeUnretainedValue()
                    .handlers[hotkeyID.id]?()
                return noErr
            },
            1, &eventType, userData, &eventHandlerRef
        )
    }
}

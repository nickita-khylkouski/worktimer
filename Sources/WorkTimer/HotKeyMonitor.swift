import Carbon
import AppKit
import Foundation

final class HotKeyMonitor {
    var onPress: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var localMonitor: Any?
    private var globalMonitor: Any?

    @discardableResult
    func install() -> Bool {
        guard hotKeyRef == nil else {
            return true
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            Self.eventHandler,
            1,
            &eventType,
            userData,
            &eventHandlerRef
        )
        guard installStatus == noErr else {
            installFallbackMonitors()
            return false
        }

        let hotKeyID = EventHotKeyID(signature: fourCharCode(from: "TKHK"), id: 1)
        let registrationStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_A),
            UInt32(cmdKey | controlKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if registrationStatus != noErr {
            installFallbackMonitors()
            return false
        }
        return true
    }

    func uninstall() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        hotKeyRef = nil
        eventHandlerRef = nil
        localMonitor = nil
        globalMonitor = nil
    }

    private static let eventHandler: EventHandlerUPP = { _, _, userData in
        guard let userData else {
            return noErr
        }
        let monitor = Unmanaged<HotKeyMonitor>.fromOpaque(userData).takeUnretainedValue()
        monitor.onPress?()
        return noErr
    }

    private func fourCharCode(from string: String) -> OSType {
        string.utf8.reduce(0) { partial, byte in
            (partial << 8) + OSType(byte)
        }
    }

    private func installFallbackMonitors() {
        if localMonitor == nil {
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard self?.matchesShortcut(event) == true else {
                    return event
                }
                self?.onPress?()
                return nil
            }
        }

        if globalMonitor == nil {
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard self?.matchesShortcut(event) == true else {
                    return
                }
                self?.onPress?()
            }
        }
    }

    private func matchesShortcut(_ event: NSEvent) -> Bool {
        event.keyCode == UInt16(kVK_ANSI_A)
            && event.modifierFlags.contains([.command, .control])
    }
}

import AppKit
import ApplicationServices
import Foundation

enum CapturePermissionState: Equatable {
    case unknown
    case ready
    case missingAccessibility
    case missingInputMonitoring
    case failedToInstallTap
}

final class TypingCaptureService: @unchecked Sendable {
    var onInput: ((TypingInput) -> Void)?
    var onHotKey: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapThread: Thread?

    func permissionState(promptIfNeeded: Bool) -> CapturePermissionState {
        let accessibilityOptions = [
            "AXTrustedCheckOptionPrompt": promptIfNeeded,
        ] as CFDictionary
        let accessibilityGranted = AXIsProcessTrustedWithOptions(accessibilityOptions)
        if !accessibilityGranted {
            return .missingAccessibility
        }

        if !Self.preflightListenAccess() {
            if promptIfNeeded {
                _ = Self.requestListenAccess()
            }
            return .missingInputMonitoring
        }

        return .ready
    }

    func start() -> CapturePermissionState {
        let state = permissionState(promptIfNeeded: false)
        guard state == .ready else {
            return state
        }

        guard eventTap == nil else {
            return .ready
        }

        let thread = Thread { [weak self] in
            self?.installTapOnCurrentThread()
        }
        thread.name = "worktimer.capture.tap"
        thread.start()
        tapThread = thread
        return .ready
    }

    func stop() {
        guard let eventTap else {
            return
        }
        if let runLoopSource {
            CFRunLoopSourceInvalidate(runLoopSource)
        }
        CFMachPortInvalidate(eventTap)
        self.eventTap = nil
        self.runLoopSource = nil
        tapThread = nil
    }

    private func installTapOnCurrentThread() {
        let mask = (1 << CGEventType.keyDown.rawValue)
        let refcon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: Self.eventTapCallback,
            userInfo: refcon
        ) else {
            return
        }

        self.eventTap = eventTap
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        self.runLoopSource = runLoopSource

        let runLoop = CFRunLoopGetCurrent()
        CFRunLoopAddSource(runLoop, runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        CFRunLoopRun()
    }

    private func process(_ event: CGEvent) {
        if Self.matchesLauncherShortcut(event) {
            DispatchQueue.main.async { [weak self] in
                DebugTrace.log("captureTap hotkey-detected")
                self?.onHotKey?()
            }
            return
        }

        guard let input = Self.makeTypingInput(from: event) else {
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.onInput?(input)
        }
    }

    private static let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        if let userInfo {
            let service = Unmanaged<TypingCaptureService>.fromOpaque(userInfo).takeUnretainedValue()
            service.process(event)
        }

        return Unmanaged.passUnretained(event)
    }

    private static func makeTypingInput(from event: CGEvent) -> TypingInput? {
        let flags = event.flags
        if flags.contains(.maskCommand) || flags.contains(.maskControl) {
            return nil
        }

        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let mutation: TypingMutation?
        switch keyCode {
        case 51, 117:
            mutation = .backspace
        case 36, 76:
            mutation = .newline
        case 48:
            mutation = .tab
        default:
            mutation = textMutation(from: event)
        }

        guard let mutation, let context = currentContext() else {
            return nil
        }

        return TypingInput(context: context, mutation: mutation)
    }

    private static func textMutation(from event: CGEvent) -> TypingMutation? {
        var length = 0
        var buffer = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(
            maxStringLength: buffer.count,
            actualStringLength: &length,
            unicodeString: &buffer
        )

        guard length > 0 else {
            return nil
        }

        let text = String(utf16CodeUnits: buffer, count: length)
        let filtered = text.filter { character in
            switch character {
            case "\u{7F}", "\u{8}", "\r", "\n", "\t":
                return false
            default:
                return !character.isASCII || character.isLetter || character.isNumber || character.isPunctuation || character.isSymbol || character == " "
            }
        }

        guard !filtered.isEmpty else {
            return nil
        }

        return .text(filtered)
    }

    private static func currentContext() -> CaptureContext? {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return nil
        }
        let bundleIdentifier = app.bundleIdentifier ?? "unknown.bundle"
        let appName = app.localizedName ?? bundleIdentifier
        return CaptureContext(
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            sessionKey: bundleIdentifier
        )
    }

    private static func preflightListenAccess() -> Bool {
        if #available(macOS 10.15, *) {
            return CGPreflightListenEventAccess()
        }
        return true
    }

    private static func requestListenAccess() -> Bool {
        if #available(macOS 10.15, *) {
            return CGRequestListenEventAccess()
        }
        return true
    }

    private static func matchesLauncherShortcut(_ event: CGEvent) -> Bool {
        let flags = event.flags
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        return keyCode == 0
            && flags.contains(.maskCommand)
            && flags.contains(.maskControl)
    }
}

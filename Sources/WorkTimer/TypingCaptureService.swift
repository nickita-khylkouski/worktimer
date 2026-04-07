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
    private var observedInputCount = 0

    func permissionState(promptIfNeeded: Bool) -> CapturePermissionState {
        let accessibilityOptions = [
            "AXTrustedCheckOptionPrompt": promptIfNeeded,
        ] as CFDictionary
        let accessibilityGranted = AXIsProcessTrustedWithOptions(accessibilityOptions)
        let listenAccessGranted = Self.preflightListenAccess()

        DebugTrace.log(
            "TypingCaptureService permission accessibility=\(accessibilityGranted) listen=\(listenAccessGranted) prompt=\(promptIfNeeded)"
        )

        // The current capture path uses a session event tap, which needs
        // Input Monitoring on modern macOS. We still prompt for
        // Accessibility because the app also relies on broader event access
        // behavior across OS versions, but listen-event approval is the
        // hard gate for starting capture.
        if listenAccessGranted {
            return .ready
        }

        if promptIfNeeded && !listenAccessGranted {
            _ = Self.requestListenAccess()
        }

        return accessibilityGranted ? .missingInputMonitoring : .missingAccessibility
    }

    func start() -> CapturePermissionState {
        let state = permissionState(promptIfNeeded: false)
        guard state == .ready else {
            DebugTrace.log("TypingCaptureService start blocked state=\(String(describing: state))")
            return state
        }

        if eventTap != nil {
            DebugTrace.log("TypingCaptureService start reused-existing-event-tap")
            return .ready
        }

        if !Thread.isMainThread {
            DispatchQueue.main.sync { [weak self] in
                self?.installEventTapIfNeeded()
            }
        } else {
            installEventTapIfNeeded()
        }

        guard eventTap != nil, runLoopSource != nil else {
            DebugTrace.log("TypingCaptureService start failed event-tap-install")
            return .failedToInstallTap
        }

        DebugTrace.log("TypingCaptureService start installed-event-tap")
        return .ready
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        observedInputCount = 0
    }

    private func installEventTapIfNeeded() {
        guard eventTap == nil else {
            return
        }

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { proxy, type, event, userInfo in
            guard let userInfo else {
                return Unmanaged.passUnretained(event)
            }

            let service = Unmanaged<TypingCaptureService>
                .fromOpaque(userInfo)
                .takeUnretainedValue()

            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let eventTap = service.eventTap {
                    CGEvent.tapEnable(tap: eventTap, enable: true)
                    DebugTrace.log("TypingCaptureService event-tap reenabled type=\(type.rawValue)")
                }
                return Unmanaged.passUnretained(event)
            }

            guard type == .keyDown else {
                return Unmanaged.passUnretained(event)
            }

            service.process(event)
            return Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            DebugTrace.log("TypingCaptureService installEventTap failed tapCreate")
            return
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            DebugTrace.log("TypingCaptureService installEventTap failed runLoopSource")
            CFMachPortInvalidate(tap)
            return
        }

        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        DebugTrace.log("TypingCaptureService installEventTap enabled=true")
    }

    private func process(_ event: CGEvent) {
        guard let event = NSEvent(cgEvent: event) else {
            return
        }

        if Self.matchesLauncherShortcut(event) {
            DebugTrace.log("typingMonitor hotkey-detected")
            onHotKey?()
            return
        }

        guard let input = Self.makeTypingInput(from: event) else {
            return
        }
        observedInputCount += 1
        if observedInputCount <= 3 || observedInputCount.isMultiple(of: 100) {
            DebugTrace.log(
                "typingMonitor input count=\(observedInputCount) app=\(input.context.appName) chars=\(Self.characterCount(for: input.mutation))"
            )
        }
        onInput?(input)
    }

    private static func makeTypingInput(from event: NSEvent) -> TypingInput? {
        if event.modifierFlags.intersection([.command, .control]).isEmpty == false {
            return nil
        }

        let keyCode = Int(event.keyCode)
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

    private static func textMutation(from event: NSEvent) -> TypingMutation? {
        guard let text = event.characters, !text.isEmpty else {
            return nil
        }

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

    private static func matchesLauncherShortcut(_ event: NSEvent) -> Bool {
        event.keyCode == 0
            && event.modifierFlags.contains([.command, .control])
    }

    private static func characterCount(for mutation: TypingMutation) -> Int {
        switch mutation {
        case let .text(text):
            return text.count
        case .newline, .tab, .backspace:
            return 1
        }
    }
}

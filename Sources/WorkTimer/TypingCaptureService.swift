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

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var observedInputCount = 0

    func permissionState(promptIfNeeded: Bool) -> CapturePermissionState {
        let accessibilityOptions = [
            "AXTrustedCheckOptionPrompt": promptIfNeeded,
        ] as CFDictionary
        let accessibilityGranted = AXIsProcessTrustedWithOptions(accessibilityOptions)
        if !accessibilityGranted {
            return .missingAccessibility
        }

        if !Self.preflightListenAccess(), promptIfNeeded {
            _ = Self.requestListenAccess()
        }

        return .ready
    }

    func start() -> CapturePermissionState {
        let state = permissionState(promptIfNeeded: false)
        guard state == .ready else {
            DebugTrace.log("TypingCaptureService start blocked state=\(String(describing: state))")
            return state
        }

        if globalMonitor != nil || localMonitor != nil {
            DebugTrace.log("TypingCaptureService start reused-existing-monitors")
            return .ready
        }

        if !Thread.isMainThread {
            DispatchQueue.main.sync { [weak self] in
                self?.installEventMonitorsIfNeeded()
            }
        } else {
            installEventMonitorsIfNeeded()
        }

        guard globalMonitor != nil || localMonitor != nil else {
            DebugTrace.log("TypingCaptureService start failed monitor-install")
            return .failedToInstallTap
        }

        DebugTrace.log("TypingCaptureService start installed-monitors")
        return .ready
    }

    func stop() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        localMonitor = nil
        globalMonitor = nil
        observedInputCount = 0
    }

    private func installEventMonitorsIfNeeded() {
        if localMonitor == nil {
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.process(event)
                return event
            }
        }

        if globalMonitor == nil {
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.process(event)
            }
        }

        DebugTrace.log(
            "TypingCaptureService installMonitors local=\(localMonitor != nil) global=\(globalMonitor != nil)"
        )
    }

    private func process(_ event: NSEvent) {
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

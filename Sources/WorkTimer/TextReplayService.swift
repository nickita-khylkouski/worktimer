import AppKit
import ApplicationServices
import Foundation

struct TextReplayService: Sendable {
    func pasteViaClipboard(_ text: String, startDelay: TimeInterval = 0.28) async {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        if startDelay > 0 {
            try? await Task.sleep(for: .seconds(startDelay))
        }

        postPasteShortcut()
    }

    func retype(_ text: String, startDelay: TimeInterval = 0.35, interKeyDelay: TimeInterval = 0.012) async {
        if startDelay > 0 {
            try? await Task.sleep(for: .seconds(startDelay))
        }

        for character in text {
            autoreleasepool {
                post(character: character)
            }
            if interKeyDelay > 0 {
                try? await Task.sleep(for: .seconds(interKeyDelay))
            }
        }
    }

    private func post(character: Character) {
        let utf16 = Array(String(character).utf16)
        guard
            let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
        else {
            return
        }

        keyDown.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        keyUp.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    private func postPasteShortcut() {
        guard
            let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: false)
        else {
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}

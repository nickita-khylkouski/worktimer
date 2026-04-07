import AppKit
import Foundation

final class RecoveryPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class RecoveryWindowManager {
    private(set) var window: RecoveryPanel?
    private var pendingAnchor: NSStatusBarButton?
    private var pendingShow = false

    func install(contentViewController: @autoclosure () -> NSViewController) {
        guard window == nil else {
            return
        }

        let panel = RecoveryPanel(
            contentRect: NSRect(x: 0, y: 0, width: 332, height: 438),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = contentViewController()
        window = panel
        configure(panel)

        if pendingShow {
            pendingShow = false
            DispatchQueue.main.async { [weak self, weak panel] in
                guard let self, let panel else {
                    return
                }
                self.position(panel, relativeTo: self.pendingAnchor)
                self.activateAndFocus(panel)
            }
        }
    }

    func toggle(relativeTo button: NSStatusBarButton?) -> Bool {
        guard let window else {
            pendingAnchor = button
            pendingShow = true
            return false
        }

        if window.isVisible {
            window.orderOut(nil)
        } else {
            position(window, relativeTo: button)
            activateAndFocus(window)
        }
        return true
    }

    func show(relativeTo button: NSStatusBarButton?) {
        guard let window else {
            pendingAnchor = button
            pendingShow = true
            return
        }

        position(window, relativeTo: button)
        activateAndFocus(window)
    }

    func hide() {
        window?.orderOut(nil)
    }

    private func configure(_ window: RecoveryPanel) {
        window.title = "WorkTimer"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isFloatingPanel = true
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.hidesOnDeactivate = true
        window.becomesKeyOnlyIfNeeded = false
        window.isReleasedWhenClosed = false
        window.animationBehavior = .utilityWindow
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
    }

    private func position(_ window: NSWindow, relativeTo button: NSStatusBarButton?) {
        guard let button,
              let buttonWindow = button.window
        else {
            window.center()
            return
        }

        let buttonFrameOnScreen = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        guard let screen = buttonWindow.screen ?? NSScreen.main else {
            window.center()
            return
        }

        let panelSize = window.frame.size
        let visibleFrame = screen.visibleFrame
        let targetX = buttonFrameOnScreen.midX - (panelSize.width / 2)
        let targetY = buttonFrameOnScreen.minY - panelSize.height - 8

        let clampedX = min(
            max(targetX, visibleFrame.minX + 12),
            visibleFrame.maxX - panelSize.width - 12
        )
        let clampedY = max(targetY, visibleFrame.minY + 12)

        window.setFrameOrigin(NSPoint(x: clampedX, y: clampedY))
    }

    private func activateAndFocus(_ window: RecoveryPanel) {
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        window.orderFrontRegardless()
        window.makeMain()
        window.makeKeyAndOrderFront(nil)
    }
}

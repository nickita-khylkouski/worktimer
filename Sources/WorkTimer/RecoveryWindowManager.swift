import AppKit
import Foundation

final class RecoveryPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class DailyDetailPanel: NSPanel {
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
            contentRect: NSRect(x: 0, y: 0, width: 368, height: 520),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
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
        window.minSize = NSSize(width: 344, height: 420)
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

@MainActor
final class DailyDetailWindowManager {
    private(set) var window: DailyDetailPanel?
    private let defaultSize = NSSize(width: 430, height: 560)
    private let minimumSize = NSSize(width: 390, height: 460)

    func install(contentViewController: @autoclosure () -> NSViewController) {
        guard window == nil else {
            return
        }

        let panel = DailyDetailPanel(
            contentRect: NSRect(origin: .zero, size: defaultSize),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = contentViewController()
        panel.title = "Day Details"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = true
        panel.isReleasedWhenClosed = false
        panel.minSize = minimumSize
        window = panel
    }

    func show(relativeTo parent: NSWindow?) {
        guard let window else {
            return
        }

        ensureUsableFrame(for: window)

        if let parent {
            let parentFrame = parent.frame
            let screenFrame = parent.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
            let desiredX = parentFrame.maxX + 14
            let desiredY = max(parentFrame.maxY - window.frame.height, parentFrame.minY)
            if let screenFrame {
                let clampedX = min(desiredX, screenFrame.maxX - window.frame.width - 12)
                let clampedY = max(screenFrame.minY + 12, min(desiredY, screenFrame.maxY - window.frame.height - 12))
                window.setFrameOrigin(NSPoint(x: clampedX, y: clampedY))
            } else {
                window.setFrameOrigin(NSPoint(x: desiredX, y: desiredY))
            }
        } else {
            window.center()
        }

        NSRunningApplication.current.activate(options: [.activateAllWindows])
        window.orderFrontRegardless()
        window.makeMain()
        window.makeKeyAndOrderFront(nil)
    }

    func hide() {
        window?.orderOut(nil)
    }

    private func ensureUsableFrame(for window: NSWindow) {
        let targetWidth = max(defaultSize.width, minimumSize.width)
        let targetHeight = max(defaultSize.height, minimumSize.height)
        guard window.frame.width < targetWidth || window.frame.height < targetHeight else {
            return
        }

        var nextFrame = window.frame
        let maxY = nextFrame.maxY
        nextFrame.size.width = targetWidth
        nextFrame.size.height = targetHeight
        nextFrame.origin.y = maxY - targetHeight
        window.setFrame(nextFrame, display: false)
    }
}

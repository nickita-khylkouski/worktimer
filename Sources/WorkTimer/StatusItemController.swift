import AppKit
import Foundation

@MainActor
final class StatusItemController: NSObject {
    private static let runningIcon = loadIcon(named: "StatusIconRunning")
    private static let pausedIcon = loadIcon(named: "StatusIconPaused")

    var onLeftClick: (() -> Void)?
    var onDoubleLeftClick: (() -> Void)?
    var onRightClick: (() -> Void)?

    var button: NSStatusBarButton? {
        statusItem.button
    }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var pendingLeftClickWorkItem: DispatchWorkItem?
    private var lastLeftClickTimestamp: TimeInterval?

    override init() {
        super.init()
        DebugTrace.log("StatusItemController init buttonExists=\(statusItem.button != nil)")
        configureButton()
    }

    func update(
        displayText: String,
        isRunning: Bool,
        displayMode: AppModel.MenuBarDisplayMode
    ) {
        guard let button = statusItem.button else {
            DebugTrace.log("StatusItemController update skipped button=nil")
            return
        }
        DebugTrace.log("StatusItemController update mode=\(displayMode.rawValue) running=\(isRunning) titleBefore=\(button.title)")

        statusItem.isVisible = true
        button.toolTip = isRunning
            ? "Timer running. Left click to pause. Double click or right click for controls."
            : "Timer paused. Left click to resume. Double click or right click for controls."
        button.appearsDisabled = false
        button.isEnabled = true

        if displayMode == .iconOnly {
            statusItem.length = NSStatusItem.squareLength
            button.title = ""
            button.font = nil
            button.image = isRunning ? Self.runningIcon : Self.pausedIcon
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
            button.contentTintColor = nil
            DebugTrace.log("StatusItemController compact icon imageLoaded=\((isRunning ? Self.runningIcon : Self.pausedIcon) != nil)")
            return
        }

        let width = textWidth(for: displayText, font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium))
        statusItem.length = max(64, width + 14)
        button.image = nil
        button.imagePosition = .noImage
        button.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        button.title = displayText
        button.contentTintColor = isRunning ? .labelColor : .secondaryLabelColor
        button.sizeToFit()
        DebugTrace.log("StatusItemController expanded width=\(button.frame.width) statusLength=\(statusItem.length)")
    }

    @objc
    private func handleClick() {
        guard let event = NSApp.currentEvent else {
            onLeftClick?()
            return
        }

        switch event.type {
        case .rightMouseUp:
            cancelPendingLeftClick()
            onRightClick?()
        case .leftMouseUp:
            handleLeftMouseUp(event)
        default:
            onLeftClick?()
        }
    }

    private func handleLeftMouseUp(_ event: NSEvent) {
        let forgivingDoubleClickInterval = max(NSEvent.doubleClickInterval, 0.45)
        let happenedQuicklyAfterFirstClick = {
            guard let lastLeftClickTimestamp else {
                return false
            }
            return (event.timestamp - lastLeftClickTimestamp) <= forgivingDoubleClickInterval
        }()

        if event.clickCount >= 2 || happenedQuicklyAfterFirstClick {
            cancelPendingLeftClick()
            onDoubleLeftClick?()
            return
        }

        lastLeftClickTimestamp = event.timestamp
        let workItem = DispatchWorkItem { [weak self] in
            self?.pendingLeftClickWorkItem = nil
            self?.lastLeftClickTimestamp = nil
            self?.onLeftClick?()
        }
        pendingLeftClickWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + forgivingDoubleClickInterval, execute: workItem)
    }

    private func cancelPendingLeftClick() {
        pendingLeftClickWorkItem?.cancel()
        pendingLeftClickWorkItem = nil
        lastLeftClickTimestamp = nil
    }

    private func configureButton() {
        guard let button = statusItem.button else {
            DebugTrace.log("StatusItemController configureButton button=nil")
            return
        }
        DebugTrace.log("StatusItemController configureButton button-ok")

        button.target = self
        button.action = #selector(handleClick)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func textWidth(for text: String, font: NSFont) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
        ]
        return NSAttributedString(string: text, attributes: attributes).size().width
    }

    private static func loadIcon(named name: String) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url)
        else {
            return nil
        }

        image.isTemplate = false
        return image
    }
}

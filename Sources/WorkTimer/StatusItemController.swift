import AppKit
import Foundation

@MainActor
final class StatusItemController: NSObject {
    private static let runningIcon = loadTemplateIcon(named: "StatusIconRunning")
    private static let pausedIcon = loadTintedIcon(named: "StatusIconPaused", color: .systemRed)

    var onLeftClick: (() -> Void)?
    var onDoubleLeftClick: (() -> Void)?
    var onRightClick: (() -> Void)?

    var button: NSStatusBarButton? {
        statusItem.button
    }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var pendingLeftClickWorkItem: DispatchWorkItem?
    private var lastLeftClickTimestamp: TimeInterval?
    private var lastCommittedLeftClickTimestamp: TimeInterval?

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
            button.attributedTitle = NSAttributedString(string: "")
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
        let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        let textColor = isRunning ? NSColor.labelColor : NSColor.systemRed
        button.font = nil
        button.title = ""
        button.attributedTitle = NSAttributedString(string: "")
        button.image = renderedTextImage(text: displayText, font: font, color: textColor)
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        button.contentTintColor = nil
        button.sizeToFit()
        DebugTrace.log("StatusItemController expanded width=\(button.frame.width) statusLength=\(statusItem.length)")
    }

    @objc
    private func handleButtonAction() {
        guard let event = NSApp.currentEvent else {
            onLeftClick?()
            return
        }

        switch event.type {
        case .rightMouseDown, .rightMouseUp:
            DebugTrace.log("StatusItemController handleRightClick type=\(event.type.rawValue) timestamp=\(event.timestamp)")
            cancelPendingLeftClick()
            onRightClick?()
        case .leftMouseUp:
            DebugTrace.log("StatusItemController handleLeftClick clickCount=\(event.clickCount) timestamp=\(event.timestamp)")
            handleLeftMouseUp(event)
        default:
            DebugTrace.log("StatusItemController ignored event type=\(event.type.rawValue)")
        }
    }

    private func handleLeftMouseUp(_ event: NSEvent) {
        let forgivingDoubleClickInterval = min(max(NSEvent.doubleClickInterval * 0.55, 0.18), 0.28)

        if let lastCommittedLeftClickTimestamp,
           (event.timestamp - lastCommittedLeftClickTimestamp) < 0.35
        {
            DebugTrace.log("StatusItemController ignored rapid repeat left click")
            return
        }

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
            self?.lastCommittedLeftClickTimestamp = event.timestamp
            DebugTrace.log("StatusItemController committed single left click")
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
        button.action = #selector(handleButtonAction)
        button.sendAction(on: [.leftMouseUp, .rightMouseDown, .rightMouseUp])
    }

    private func textWidth(for text: String, font: NSFont) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
        ]
        return NSAttributedString(string: text, attributes: attributes).size().width
    }

    private func renderedTextImage(text: String, font: NSFont, color: NSColor) -> NSImage? {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
        ]
        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributedString.size()
        guard textSize.width > 0, textSize.height > 0 else {
            return nil
        }

        let imageSize = NSSize(width: ceil(textSize.width), height: ceil(textSize.height))
        let image = NSImage(size: imageSize)
        image.lockFocus()
        attributedString.draw(
            at: NSPoint(
                x: 0,
                y: (imageSize.height - textSize.height) / 2
            )
        )
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private static func loadTemplateIcon(named name: String) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url)
        else {
            return nil
        }

        let trimmed = trimTransparentPadding(from: image) ?? image
        trimmed.isTemplate = true
        return trimmed
    }

    private static func trimTransparentPadding(from image: NSImage) -> NSImage? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let cgImage = bitmap.cgImage,
              let croppedCGImage = cgImage.cropping(to: nonTransparentBounds(in: cgImage))
        else {
            return nil
        }

        let trimmed = NSImage(cgImage: croppedCGImage, size: NSSize(width: croppedCGImage.width, height: croppedCGImage.height))
        trimmed.isTemplate = image.isTemplate
        return trimmed
    }

    private static func nonTransparentBounds(in image: CGImage) -> CGRect {
        guard let dataProvider = image.dataProvider,
              let data = dataProvider.data,
              let bytes = CFDataGetBytePtr(data)
        else {
            return CGRect(x: 0, y: 0, width: image.width, height: image.height)
        }

        let width = image.width
        let height = image.height
        let bytesPerRow = image.bytesPerRow
        let alphaIndex = 3

        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1

        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + (x * 4)
                let alpha = bytes[offset + alphaIndex]
                guard alpha > 0 else {
                    continue
                }
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }

        guard maxX >= minX, maxY >= minY else {
            return CGRect(x: 0, y: 0, width: width, height: height)
        }

        return CGRect(
            x: minX,
            y: minY,
            width: maxX - minX + 1,
            height: maxY - minY + 1
        )
    }

    private static func loadTintedIcon(named name: String, color: NSColor) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let sourceImage = NSImage(contentsOf: url)
        else {
            return nil
        }

        let baseImage = trimTransparentPadding(from: sourceImage) ?? sourceImage
        let tintedImage = NSImage(size: baseImage.size)
        tintedImage.lockFocus()
        let bounds = NSRect(origin: .zero, size: baseImage.size)
        baseImage.draw(in: bounds)
        color.set()
        bounds.fill(using: .sourceAtop)
        tintedImage.unlockFocus()
        tintedImage.isTemplate = false
        return tintedImage
    }
}

import AppKit
import Foundation

final class MouseCaptureService: @unchecked Sendable {
    var onSample: ((MouseMovementSample) -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var observedMoveCount = 0

    func start() -> Bool {
        if globalMonitor != nil || localMonitor != nil {
            DebugTrace.log("MouseCaptureService start reused-existing-monitors")
            return true
        }

        if !Thread.isMainThread {
            DispatchQueue.main.sync { [weak self] in
                self?.installMonitorsIfNeeded()
            }
        } else {
            installMonitorsIfNeeded()
        }

        let installed = globalMonitor != nil || localMonitor != nil
        DebugTrace.log("MouseCaptureService start installed=\(installed)")
        return installed
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
        observedMoveCount = 0
    }

    private func installMonitorsIfNeeded() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]

        if localMonitor == nil {
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
                self?.process(event)
                return event
            }
        }

        if globalMonitor == nil {
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
                self?.process(event)
            }
        }
    }

    private func process(_ event: NSEvent) {
        let deltaX = Double(event.deltaX)
        let deltaY = Double(event.deltaY)
        let pointDistance = hypot(deltaX, deltaY)
        guard pointDistance >= 0.5 else {
            return
        }

        let location = Self.eventLocation(event)
        let estimatedMillimeters = Self.estimatedMillimeters(
            deltaX: deltaX,
            deltaY: deltaY,
            location: location
        ) ?? 0

        observedMoveCount += 1
        if observedMoveCount <= 3 || observedMoveCount.isMultiple(of: 200) {
            DebugTrace.log(
                "mouseMonitor move count=\(observedMoveCount) points=\(String(format: "%.2f", pointDistance)) mm=\(String(format: "%.2f", estimatedMillimeters))"
            )
        }

        onSample?(MouseMovementSample(pointDistance: pointDistance, estimatedMillimeters: estimatedMillimeters))
    }

    private static func eventLocation(_ event: NSEvent) -> CGPoint {
        return NSEvent.mouseLocation
    }

    private static func estimatedMillimeters(deltaX: Double, deltaY: Double, location: CGPoint) -> Double? {
        guard let screen = screen(containing: location),
              let displayID = displayID(for: screen)
        else {
            return nil
        }

        let physicalSizeMM = CGDisplayScreenSize(displayID)
        let pixelWidth = CGFloat(CGDisplayPixelsWide(displayID))
        let pixelHeight = CGFloat(CGDisplayPixelsHigh(displayID))
        guard physicalSizeMM.width > 0, physicalSizeMM.height > 0, pixelWidth > 0, pixelHeight > 0 else {
            return nil
        }

        let scale = screen.backingScaleFactor
        let xMillimeters = abs(deltaX) * scale * Double(physicalSizeMM.width / pixelWidth)
        let yMillimeters = abs(deltaY) * scale * Double(physicalSizeMM.height / pixelHeight)
        return hypot(xMillimeters, yMillimeters)
    }

    private static func screen(containing location: CGPoint) -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(location, $0.frame, false) } ?? NSScreen.main
    }

    private static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(screenNumber.uint32Value)
    }
}

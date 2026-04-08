import AppKit
import SwiftUI

final class WorkTimerApplicationDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        DebugTrace.log("WorkTimer applicationDidFinishLaunching")

        if terminateIfDuplicateInstanceExists() {
            return
        }

        NSApplication.shared.setActivationPolicy(.regular)

        let model = AppModel()
        self.model = model

        model.installRecoveryPanel {
            TimerPanelView(model: model)
        }
        model.installDailyDetailPanel {
            DailySummaryPanelView(model: model)
        }
        model.startIfNeeded()
        LaunchAtLoginManager.ensureEnabled()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        model?.openControlPanel()
        return true
    }

    @MainActor
    private func terminateIfDuplicateInstanceExists() -> Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            return false
        }

        let currentPID = ProcessInfo.processInfo.processIdentifier
        let duplicates = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { $0.processIdentifier != currentPID }

        guard let existing = duplicates.first else {
            return false
        }

        DebugTrace.log("WorkTimer duplicate detected existingPID=\(existing.processIdentifier) currentPID=\(currentPID)")
        existing.activate(options: [])
        NSApp.terminate(nil)
        return true
    }
}

@main
struct WorkTimerApplication {
    static func main() {
        let app = NSApplication.shared
        let delegate = WorkTimerApplicationDelegate()
        app.delegate = delegate
        app.run()
    }
}

import Foundation
import ServiceManagement

@MainActor
enum LaunchAtLoginManager {
    static func ensureEnabled() {
        let service = SMAppService.mainApp

        switch service.status {
        case .enabled:
            DebugTrace.log("LaunchAtLogin already enabled")
        case .requiresApproval:
            DebugTrace.log("LaunchAtLogin requires approval in System Settings")
        case .notRegistered, .notFound:
            do {
                try service.register()
                DebugTrace.log("LaunchAtLogin registration succeeded")
            } catch {
                DebugTrace.log("LaunchAtLogin registration failed error=\(error.localizedDescription)")
            }
        @unknown default:
            DebugTrace.log("LaunchAtLogin unknown status")
        }
    }
}

import Foundation
import ServiceManagement

@MainActor
enum LaunchAtLoginManager {
    enum StatusSummary: Equatable {
        case enabled
        case requiresApproval
        case unavailable

        var label: String {
            switch self {
            case .enabled:
                return "Ready"
            case .requiresApproval:
                return "Needs Approval"
            case .unavailable:
                return "Unavailable"
            }
        }

        var detail: String {
            switch self {
            case .enabled:
                return "WorkTimer is registered to launch at login."
            case .requiresApproval:
                return "Approve WorkTimer in Login Items if macOS asks."
            case .unavailable:
                return "WorkTimer could not verify launch-at-login on this Mac."
            }
        }
    }

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

    static func currentStatus() -> StatusSummary {
        let service = SMAppService.mainApp

        switch service.status {
        case .enabled:
            return .enabled
        case .requiresApproval, .notRegistered, .notFound:
            return .requiresApproval
        @unknown default:
            return .unavailable
        }
    }
}

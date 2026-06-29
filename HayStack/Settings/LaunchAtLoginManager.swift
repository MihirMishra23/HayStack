import Foundation
import ServiceManagement

enum LaunchAtLoginError: LocalizedError {
    case requiresApproval
    case notFound

    var errorDescription: String? {
        switch self {
        case .requiresApproval:
            return "Approve HayStack in System Settings → General → Login Items."
        case .notFound:
            return "Open at Login is only available for a built HayStack.app, not when running from Xcode."
        }
    }
}

@MainActor
final class LaunchAtLoginManager: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var statusMessage: String?

    init() {
        refreshStatus()
    }

    func refreshStatus() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled
        statusMessage = Self.message(for: status)
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }

        refreshStatus()

        if enabled, SMAppService.mainApp.status == .requiresApproval {
            throw LaunchAtLoginError.requiresApproval
        }
        if enabled, SMAppService.mainApp.status == .notFound {
            throw LaunchAtLoginError.notFound
        }
    }

    private static func message(for status: SMAppService.Status) -> String? {
        switch status {
        case .enabled:
            return "HayStack will start automatically when you log in."
        case .requiresApproval:
            return "Waiting for approval in System Settings → General → Login Items."
        case .notRegistered:
            return "HayStack starts only when you open it."
        case .notFound:
            return "Install HayStack.app to /Applications to use Open at Login."
        @unknown default:
            return nil
        }
    }
}

import ServiceManagement

/// Launch-at-login via `SMAppService` (macOS 13+), which replaces the deprecated
/// `SMLoginItemSetEnabled` and needs no helper bundle.
@MainActor
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// macOS may require the user to approve the item in System Settings; surfaced so the UI
    /// can explain rather than silently appearing not to work.
    static var requiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    @discardableResult
    static func set(_ enabled: Bool) -> Result<Void, Error> {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            return .success(())
        } catch {
            return .failure(error)
        }
    }
}

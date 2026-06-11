import AppKit
import ServiceManagement

extension AppDelegate {
    func isLaunchAtLoginOnOrPending() -> Bool {
        let status = SMAppService.mainApp.status
        return status == .enabled || status == .requiresApproval
    }

    func setLaunchAtLogin(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            showLaunchAtLoginError(error)
        }

        let status = SMAppService.mainApp.status
        if enabled && status == .requiresApproval {
            let alert = NSAlert()
            alert.messageText = "需要授权"
            alert.informativeText = "请在 系统设置 > 通用 > 登录项 中允许 LookAway。"
            alert.alertStyle = .informational
            alert.runModal()
        }

        launchAtLogin = isLaunchAtLoginOnOrPending()
        return launchAtLogin
    }

    func showLaunchAtLoginError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "无法设置登录时启动"
        alert.informativeText = "请先将 LookAway.app 移动到「应用程序」文件夹后再开启。错误：\(error.localizedDescription)"
        alert.alertStyle = .warning
        alert.runModal()
    }
}

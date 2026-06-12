import AppKit

final class VideoPauser {
    private static func isInstalledAndRunning(_ bundleID: String) -> Bool {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil else {
            return false
        }
        return !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    /// 在主线程判断哪些播放器正在运行，返回目标标识列表（供后台导暂停使用）
    static func runningTargets() -> [String] {
        var targets: [String] = []
        if isInstalledAndRunning("com.apple.Safari") { targets.append("safari") }
        if isInstalledAndRunning("com.google.Chrome") { targets.append("chrome") }
        if isInstalledAndRunning("com.microsoft.Edge") { targets.append("edge") }
        if isInstalledAndRunning("company.thebrowser.Browser") { targets.append("arc") }
        if isInstalledAndRunning("com.brave.Browser") { targets.append("brave") }
        if isInstalledAndRunning("com.apple.QuickTimePlayerX") { targets.append("quicktime") }
        return targets
    }

    /// 异步执行指定目标的暂停操作
    static func pauseTargetsAsync(_ targets: [String]) {
        for target in targets {
            switch target {
            case "safari": pauseSafari()
            case "chrome": pauseChromiumBrowser("Google Chrome")
            case "edge": pauseChromiumBrowser("Microsoft Edge")
            case "arc": pauseChromiumBrowser("Arc")
            case "brave": pauseChromiumBrowser("Brave")
            case "quicktime": pauseQuickTime()
            default: break
            }
        }
    }

    private static func runOsaScriptAsync(_ source: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        do {
            try process.run()
        } catch {
            NSLog("LookAway 视频暂停器 osascript 运行错误: \(error)")
        }
    }

    private static func pauseSafari() {
        let script = """
        tell application "Safari"
            if exists front window then
                tell front window
                    tell current tab
                        do JavaScript "document.querySelectorAll('video').forEach(v => { if(!v.paused && !v.ended) v.pause(); })"
                    end tell
                end tell
            end if
        end tell
        """
        runOsaScriptAsync(script)
    }

    private static func pauseChromiumBrowser(_ appName: String) {
        let script = """
        tell application "\(appName)"
            if exists front window then
                tell front window
                    tell active tab
                        execute javascript "document.querySelectorAll('video').forEach(v => { if(!v.paused && !v.ended) v.pause(); })"
                    end tell
                end tell
            end if
        end tell
        """
        runOsaScriptAsync(script)
    }

    private static func pauseQuickTime() {
        let script = """
        tell application "QuickTime Player"
            pause every document
        end tell
        """
        runOsaScriptAsync(script)
    }
}

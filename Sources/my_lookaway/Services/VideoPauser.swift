import AppKit

final class VideoPauser {
    private static func isInstalledAndRunning(_ bundleID: String) -> Bool {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil else {
            return false
        }
        return !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    /// 在主线程判断哪些播放器正在运行，返回目标标识列表（供后台异步暂停用）
    static func runningTargets() -> [String] {
        var targets: [String] = []
        if isInstalledAndRunning("com.apple.Safari") { targets.append("safari") }
        if isInstalledAndRunning("com.google.Chrome") { targets.append("chrome") }
        if isInstalledAndRunning("com.apple.QuickTimePlayerX") { targets.append("quicktime") }
        return targets
    }

    /// 在后台异步执行指定目标的 AppleScript 暂停（NSWorkspace 查询已在主线程完成）
    static func pauseTargetsAsync(_ targets: [String]) {
        DispatchQueue.global(qos: .utility).async {
            autoreleasepool {
                for target in targets {
                    switch target {
                    case "safari": pauseSafari()
                    case "chrome": pauseChrome()
                    case "quicktime": pauseQuickTime()
                    default: break
                    }
                }
            }
        }
    }

    private static func runAppleScript(_ source: String) {
        guard let script = NSAppleScript(source: source) else { return }
        var errorInfo: NSDictionary?
        script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            NSLog("LookAway 视频暂停器 AppleScript 错误: \(errorInfo)")
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
        runAppleScript(script)
    }

    private static func pauseChrome() {
        let script = """
        tell application "Google Chrome"
            if exists front window then
                tell front window
                    tell active tab
                        execute javascript "document.querySelectorAll('video').forEach(v => { if(!v.paused && !v.ended) v.pause(); })"
                    end tell
                end tell
            end if
        end tell
        """
        runAppleScript(script)
    }

    private static func pauseQuickTime() {
        let script = """
        tell application "QuickTime Player"
            pause every document
        end tell
        """
        runAppleScript(script)
    }
}

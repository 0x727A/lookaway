import SwiftUI
import AppKit

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var statusItem: NSStatusItem!
    var workTimer: Timer?
    var restWindows: [NSWindow] = []
    var restSession: RestSession?
    var settingsWindow: NSWindow?
    var countdownSeconds = 20 * 60
    var isPaused = false
    var workEndDate: Date?

    // 可配置的时间
    var workDurationMinutes = 20
    var restDurationSeconds = 20
    var isForceRestMode = false
    var playSoundOnRestEnd = true
    var playSoundOnRestStart = true
    var restStartSoundName = "Ping"
    var restEndSoundName = "Glass"
    var pauseVideoOnRestStart = false
    var launchAtLogin = false
    var displayMode = DisplayMode.iconAndTime.rawValue // persisted raw value
    var dotPulseOn = false
    var singleClickWorkItem: DispatchWorkItem?
    var pendingShowSettings = false
    var quitMenuItem: NSMenuItem?
    var isSystemSuspended = false   // LookAway 已因系统/屏幕/会话非活跃暂停倒计时
    var isSleepInactive = false     // 系统睡眠
    var isScreenInactive = false    // 屏幕睡眠/黑屏
    var isSessionInactive = false   // 锁屏/会话非活跃
    var suspendDate: Date?

    var currentDisplayMode: DisplayMode {
        DisplayMode(rawValue: displayMode) ?? .iconAndTime
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 单实例检查
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.lookaway.app"
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        let otherInstances = runningApps.filter { $0.processIdentifier != currentPID }
        if !otherInstances.isEmpty {
            otherInstances.first?.activate(options: [])
            NSApp.terminate(nil)
            return
        }

        // 进程名兜底：防止旧包 bundle id 不同也能同时运行
        let runningLookAwayApps = NSWorkspace.shared.runningApplications.filter {
            $0.processIdentifier != currentPID &&
            ($0.localizedName == "LookAway" || $0.bundleURL?.lastPathComponent == "LookAway.app")
        }
        if !runningLookAwayApps.isEmpty {
            runningLookAwayApps.first?.activate(options: [])
            NSApp.terminate(nil)
            return
        }

        NSApp.setActivationPolicy(.accessory)

        // 加载持久化设置
        let defaults = UserDefaults.standard
        workDurationMinutes = defaults.object(forKey: DefaultsKey.workDurationMinutes) as? Int ?? 20
        restDurationSeconds = defaults.object(forKey: DefaultsKey.restDurationSeconds) as? Int ?? 20
        isForceRestMode = defaults.object(forKey: DefaultsKey.isForceRestMode) as? Bool ?? false
        playSoundOnRestEnd = defaults.object(forKey: DefaultsKey.playSoundOnRestEnd) as? Bool ?? true
        playSoundOnRestStart = defaults.object(forKey: DefaultsKey.playSoundOnRestStart) as? Bool ?? true
        let oldSound = defaults.string(forKey: DefaultsKey.alertSoundName)
        restStartSoundName = safeSound(defaults.string(forKey: DefaultsKey.restStartSoundName) ?? oldSound, fallback: "Ping")
        restEndSoundName = safeSound(defaults.string(forKey: DefaultsKey.restEndSoundName) ?? oldSound, fallback: "Glass")
        pauseVideoOnRestStart = defaults.object(forKey: DefaultsKey.pauseVideoOnRestStart) as? Bool ?? false
        displayMode = defaults.object(forKey: DefaultsKey.displayMode) as? Int ?? 0
        countdownSeconds = workDurationMinutes * 60

        statusItem = NSStatusBar.system.statusItem(withLength: 58)
        applyStatusItemLength()
        updateMenuTitle()

        // 原生菜单
        let menu = NSMenu()
        let pauseItem = NSMenuItem(title: "开始/暂停", action: nil, keyEquivalent: "")
        pauseItem.target = self
        pauseItem.action = #selector(togglePause)
        menu.addItem(pauseItem)
        let restItem = NSMenuItem(title: "立即休息", action: nil, keyEquivalent: "")
        restItem.target = self
        restItem.action = #selector(startRestNow)
        menu.addItem(restItem)
        let settingsItem = NSMenuItem(title: "设置...", action: nil, keyEquivalent: "")
        settingsItem.target = self
        settingsItem.action = #selector(showSettings)
        menu.addItem(settingsItem)
        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)
        quitMenuItem = quitItem
        statusItem.menu = menu
        updateMenuState()

        startWorkTimer()

        // 监听系统睡眠/唤醒/屏幕/会话
        let center = NSWorkspace.shared.notificationCenter

        center.addObserver(self, selector: #selector(systemWillSuspend),
                           name: NSWorkspace.willSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(systemDidResume),
                           name: NSWorkspace.didWakeNotification, object: nil)
        center.addObserver(self, selector: #selector(screenDidSleep),
                           name: NSWorkspace.screensDidSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(screenDidWake),
                           name: NSWorkspace.screensDidWakeNotification, object: nil)
        center.addObserver(self, selector: #selector(sessionDidResignActive),
                           name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(sessionDidBecomeActive),
                           name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)

        // Distributed Notification：锁屏/解锁（覆盖 Command+Control+Q）
        let distributedCenter = DistributedNotificationCenter.default()
        distributedCenter.addObserver(
            self,
            selector: #selector(screenIsLocked),
            name: Notification.Name("com.apple.screenIsLocked"),
            object: nil
        )
        distributedCenter.addObserver(
            self,
            selector: #selector(screenIsUnlocked),
            name: Notification.Name("com.apple.screenIsUnlocked"),
            object: nil
        )

        // 监听屏幕分辨率/插拔状态变更
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
        NotificationCenter.default.removeObserver(self)

        workTimer?.invalidate()
        workTimer = nil

        restSession?.invalidate()
        restSession = nil
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if isForceRestMode && !restWindows.isEmpty {
            return .terminateCancel
        }
        return .terminateNow
    }

    @objc func quit() {
        guard !(isForceRestMode && !restWindows.isEmpty) else { return }
        NSApplication.shared.terminate(nil)
    }
}

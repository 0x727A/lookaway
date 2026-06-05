import SwiftUI
import AppKit
import ServiceManagement

enum DefaultsKey {
    static let workDurationMinutes = "LookAway.workDurationMinutes"
    static let restDurationSeconds = "LookAway.restDurationSeconds"
    static let isForceRestMode = "LookAway.isForceRestMode"
    static let playSoundOnRestEnd = "LookAway.playSoundOnRestEnd"
    static let displayMode = "LookAway.displayMode"
}

@main
struct LookAwayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class RestSession: ObservableObject {
    @Published var remainingSeconds: Int
    @Published var progress: CGFloat = 1
    
    private let duration: Int
    private let startTime = Date()
    private var timer: Timer?
    private let onComplete: () -> Void
    
    init(duration: Int, onComplete: @escaping () -> Void) {
        let safeDuration = max(1, duration)
        self.duration = safeDuration
        self.remainingSeconds = safeDuration
        self.onComplete = onComplete
        start()
    }
    
    func start() {
        timer?.invalidate()
        timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }
    
    func tick() {
        let elapsed = Date().timeIntervalSince(startTime)
        let remaining = max(0, Double(duration) - elapsed)
        
        remainingSeconds = Int(ceil(remaining))
        progress = CGFloat(remaining / Double(duration))
        
        if remaining <= 0 {
            progress = 0
            remainingSeconds = 0
            timer?.invalidate()
            timer = nil
            onComplete()
        }
    }
    
    func invalidate() {
        timer?.invalidate()
        timer = nil
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var statusItem: NSStatusItem!
    var workTimer: Timer?
    var restWindows: [NSWindow] = []
    var restSession: RestSession?
    var settingsWindow: NSWindow?
    var todayRestCount = 0
    var todayRestSeconds = 0
    var todaySkipCount = 0
    var countdownSeconds = 20 * 60
    var isPaused = false
    var workEndDate: Date?
    
    // 可配置的时间
    var workDurationMinutes = 20
    var restDurationSeconds = 20
    var isForceRestMode = false
    var playSoundOnRestEnd = true
    var launchAtLogin = false
    var displayMode = 0 // 0=图标+时间, 1=仅时间, 2=极简图标
    var dotPulseOn = false
    var singleClickWorkItem: DispatchWorkItem?
    var pendingShowSettings = false

    
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
        displayMode = defaults.object(forKey: DefaultsKey.displayMode) as? Int ?? 0
        countdownSeconds = workDurationMinutes * 60
        
        statusItem = NSStatusBar.system.statusItem(withLength: 58)
        statusItem.button?.title = "LookAway"
        statusItem.button?.image = nil
        applyStatusItemLength()
        
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
        let quitItem = NSMenuItem(title: "退出", action: nil, keyEquivalent: "")
        quitItem.target = self
        quitItem.action = #selector(quit)
        menu.addItem(quitItem)
        statusItem.menu = menu
        
        startWorkTimer()
        
        // 监听系统睡眠/唤醒
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    func startWorkTimer() {
        workTimer?.invalidate()
        workEndDate = Date().addingTimeInterval(TimeInterval(countdownSeconds))
        
        workTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }
    
    func tick() {
        guard !isPaused else { return }
        guard let endDate = workEndDate else { return }
        
        countdownSeconds = max(0, Int(ceil(endDate.timeIntervalSinceNow)))
        
        if countdownSeconds <= 0 {
            countdownSeconds = workDurationMinutes * 60
            workEndDate = nil
            showRestWindow()
            return
        }
        
        updateMenuTitle()
    }
    
    func applyStatusItemLength() {
        switch displayMode {
        case 1:
            statusItem.length = 46
        case 2:
            statusItem.length = 28
        default:
            statusItem.length = 58
        }
    }
    
    func statusItemWidth() -> CGFloat {
        switch displayMode {
        case 1: return 46
        case 2: return 28
        default: return 58
        }
    }
    
    // 当前未使用：由 button.image = NSImage(systemSymbolName:) 替代
    func renderStatusImage(width: CGFloat) -> NSImage {
        let minutes = countdownSeconds / 60
        let seconds = countdownSeconds % 60
        let timeText = String(format: "%d:%02d", minutes, seconds)
        
        // 动态选择 SF Symbol 图标
        let symbolName: String
        let iconColor: NSColor
        
        if !restWindows.isEmpty {
            symbolName = "cup.and.saucer.fill"
            iconColor = .systemOrange
        } else if isPaused {
            symbolName = "pause.fill"
            iconColor = .systemYellow
        } else if countdownSeconds <= 10 {
            symbolName = "timer"
            iconColor = .systemRed
        } else if countdownSeconds < 60 {
            symbolName = "timer"
            iconColor = .systemOrange
        } else {
            symbolName = "eye.fill"
            iconColor = .controlTextColor
        }
        
        let iconPointSize: CGFloat
        let iconWeight: NSFont.Weight
        let iconSize: CGFloat
        let iconY: CGFloat
        
        if countdownSeconds < 60 || isPaused || !restWindows.isEmpty {
            iconPointSize = 13
            iconWeight = .semibold
            iconSize = 14
            iconY = 4
        } else {
            iconPointSize = 11
            iconWeight = .regular
            iconSize = 12
            iconY = 5
        }
        
        let h: CGFloat = 22
        
        switch displayMode {
        case 1: // 仅时间
            let image = NSImage(size: NSSize(width: width, height: h))
            image.lockFocus()
            
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
                .foregroundColor: NSColor.controlTextColor
            ]
            let attr = NSAttributedString(string: timeText, attributes: attrs)
            let textSize = attr.size()
            let textRect = NSRect(
                x: (width - textSize.width) / 2,
                y: (h - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )
            attr.draw(in: textRect)
            
            image.unlockFocus()
            return image
            
        case 2: // 极简图标
            let image = NSImage(size: NSSize(width: width, height: h))
            image.lockFocus()
            
            let compactIconY: CGFloat = iconSize >= 14 ? 7 : 8
            
            if let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
                let config = NSImage.SymbolConfiguration(pointSize: iconPointSize, weight: iconWeight)
                    .applying(.init(paletteColors: [iconColor]))
                let tinted = symbol.withSymbolConfiguration(config)
                let iconRect = NSRect(
                    x: (width - iconSize) / 2,
                    y: compactIconY,
                    width: iconSize,
                    height: iconSize
                )
                tinted?.draw(in: iconRect)
            }
            
            // 底部 5 个进度点
            let activeDots: Int
            if !restWindows.isEmpty {
                activeDots = 0
            } else {
                let total = max(1, workDurationMinutes * 60)
                let progress = CGFloat(countdownSeconds) / CGFloat(total)
                activeDots = max(0, min(5, Int(ceil(progress * 5))))
            }
            
            let pulsingDotIndex = max(0, activeDots - 1)
            let shouldPulseDots = !isPaused && restWindows.isEmpty && activeDots > 0
            
            let dotSize: CGFloat = 2.2
            let spacing: CGFloat = 2.0
            let totalWidth = dotSize * 5 + spacing * 4
            let startX = (width - totalWidth) / 2
            let dotY: CGFloat = 3
            
            for index in 0..<5 {
                let isActive = index < activeDots
                let isPulsing = shouldPulseDots && index == pulsingDotIndex
                let activeAlpha: CGFloat = isPulsing ? (dotPulseOn ? 1.0 : 0.55) : 0.9
                
                let color = isActive
                    ? NSColor.white.withAlphaComponent(activeAlpha)
                    : NSColor.white.withAlphaComponent(0.28)
                
                let dotRect = NSRect(
                    x: startX + CGFloat(index) * (dotSize + spacing),
                    y: dotY,
                    width: dotSize,
                    height: dotSize
                )
                color.setFill()
                NSBezierPath(ovalIn: dotRect).fill()
            }
            
            image.unlockFocus()
            return image
            
        default: // 0 = 图标+时间
            let image = NSImage(size: NSSize(width: width, height: h))
            image.lockFocus()
            
            // 图标（左侧）
            if let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
                let config = NSImage.SymbolConfiguration(pointSize: iconPointSize, weight: iconWeight)
                    .applying(.init(paletteColors: [iconColor]))
                let tinted = symbol.withSymbolConfiguration(config)
                let iconRect = NSRect(x: 9, y: iconY, width: iconSize, height: iconSize)
                tinted?.draw(in: iconRect)
            }
            
            // 时间（右侧）
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
                .foregroundColor: NSColor.controlTextColor
            ]
            let attr = NSAttributedString(string: timeText, attributes: attrs)
            let textSize = attr.size()
            let textRect = NSRect(
                x: 20,
                y: (h - textSize.height) / 2,
                width: 40,
                height: textSize.height
            )
            attr.draw(in: textRect)
            
            image.unlockFocus()
            return image
        }
    }
    
    func updateMenuTitle() {
        guard let button = statusItem.button else { return }
        
        let minutes = countdownSeconds / 60
        let seconds = countdownSeconds % 60
        let timeText = String(format: "%d:%02d", minutes, seconds)
        
        let symbolName: String
        let iconColor: NSColor
        let iconWeight: NSFont.Weight
        if !restWindows.isEmpty {
            symbolName = "cup.and.saucer.fill"
            iconColor = .systemOrange
            iconWeight = .regular
        } else if isPaused {
            symbolName = "pause.fill"
            iconColor = .white
            iconWeight = .semibold
        } else if countdownSeconds <= 10 {
            symbolName = "timer"
            iconColor = .white
            iconWeight = .semibold
        } else if countdownSeconds < 60 {
            symbolName = "timer"
            iconColor = .white
            iconWeight = .bold
        } else {
            symbolName = "eye.fill"
            iconColor = .controlTextColor
            iconWeight = .regular
        }
        
        switch displayMode {
        case 1: // 仅时间
            button.title = timeText
            button.image = nil
        case 2: // 极简图标（只显示图标，无进度点）
            button.title = ""
            button.imagePosition = .imageOnly
            if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
                let config = NSImage.SymbolConfiguration(pointSize: 12, weight: iconWeight)
                    .applying(.init(hierarchicalColor: iconColor))
                button.image = image.withSymbolConfiguration(config)
            } else {
                button.image = nil
            }
        default: // 0=图标+时间
            button.title = timeText
            button.imagePosition = .imageLeading
            if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
                let config = NSImage.SymbolConfiguration(pointSize: 12, weight: iconWeight)
                    .applying(.init(hierarchicalColor: iconColor))
                button.image = image.withSymbolConfiguration(config)
            } else {
                button.image = nil
            }
        }
    }
    
    @objc func togglePause() {
        if isPaused {
            isPaused = false
            workEndDate = Date().addingTimeInterval(TimeInterval(countdownSeconds))
        } else {
            if let endDate = workEndDate {
                countdownSeconds = max(0, Int(ceil(endDate.timeIntervalSinceNow)))
            }
            isPaused = true
            workEndDate = nil
        }
        updateMenuTitle()
    }
    
    @objc func systemDidWake() {
        guard restWindows.isEmpty else { return }
        countdownSeconds = workDurationMinutes * 60
        if isPaused {
            workEndDate = nil
        } else {
            workEndDate = Date().addingTimeInterval(TimeInterval(countdownSeconds))
        }
        updateMenuTitle()
    }
    
    @objc func startRestNow() {
        countdownSeconds = workDurationMinutes * 60
        workEndDate = nil
        showRestWindow()
        updateMenuTitle()
    }
    
    @objc func showSettings() {
        singleClickWorkItem?.cancel()
        singleClickWorkItem = nil
        
        guard !pendingShowSettings else { return }
        pendingShowSettings = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.pendingShowSettings = false
            self?.showSettingsWindow()
        }
    }
    
    func showSettingsWindow() {
        guard settingsWindow == nil else {
            settingsWindow?.makeKeyAndOrderFront(nil)
            return
        }
        
        launchAtLogin = isLaunchAtLoginOnOrPending()
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "设置"
        window.level = .floating
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        
        let hostingView = NSHostingView(rootView: SettingsView(
            workMinutes: workDurationMinutes,
            restSeconds: restDurationSeconds,
            forceRest: isForceRestMode,
            playSound: playSoundOnRestEnd,
            launchAtLogin: launchAtLogin,
            displayMode: displayMode,
            onSave: { [weak self] work, rest, force, play, mode in
                let safeWork = max(1, work)
                let safeRest = max(5, rest)
                
                let oldWorkDuration = self?.workDurationMinutes
                let workDurationChanged = oldWorkDuration != safeWork
                
                let defaults = UserDefaults.standard
                defaults.set(safeWork, forKey: DefaultsKey.workDurationMinutes)
                defaults.set(safeRest, forKey: DefaultsKey.restDurationSeconds)
                defaults.set(force, forKey: DefaultsKey.isForceRestMode)
                defaults.set(play, forKey: DefaultsKey.playSoundOnRestEnd)
                defaults.set(mode, forKey: DefaultsKey.displayMode)
                
                self?.workDurationMinutes = safeWork
                self?.restDurationSeconds = safeRest
                self?.isForceRestMode = force
                self?.playSoundOnRestEnd = play
                self?.displayMode = mode
                
                if mode == 2 {
                    self?.dotPulseOn = true
                }
                
                if workDurationChanged {
                    self?.countdownSeconds = safeWork * 60
                    if self?.isPaused == false && self?.restWindows.isEmpty == true {
                        self?.workEndDate = Date().addingTimeInterval(TimeInterval(safeWork * 60))
                    } else {
                        self?.workEndDate = nil
                    }
                }
                
                self?.applyStatusItemLength()
                self?.updateMenuTitle()
                self?.settingsWindow?.close()
            },
            onCancel: { [weak self] in
                self?.settingsWindow?.close()
            },
            onLaunchAtLoginChange: { [weak self] enabled in
                self?.setLaunchAtLogin(enabled) ?? false
            }
        ))
        window.contentView = hostingView
        
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === settingsWindow else { return }
        
        let window = settingsWindow
        window?.delegate = nil
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            window?.contentView = nil
            self?.settingsWindow = nil
        }
    }
    
    func showRestWindow() {
        guard restWindows.isEmpty else { return }
        
        workTimer?.invalidate()
        workTimer = nil
        
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            startWorkTimer()
            return
        }
        
        restSession = RestSession(duration: restDurationSeconds) { [weak self] in
            self?.closeRestWindow(playSound: self?.playSoundOnRestEnd ?? true, skipped: false)
        }
        
        guard let session = restSession else {
            startWorkTimer()
            return
        }
        
        for screen in screens {
            let frame = screen.frame
            
            let window = NSWindow(
                contentRect: frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.level = .screenSaver
            window.backgroundColor = isForceRestMode ? .black : NSColor.black.withAlphaComponent(0.85)
            window.isOpaque = false
            window.ignoresMouseEvents = isForceRestMode
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            
            let hostingView = NSHostingView(rootView: RestView(
                session: session,
                isForceMode: isForceRestMode,
                onSkip: { [weak self] in
                    self?.closeRestWindow(playSound: false, skipped: true)
                }
            ))
            hostingView.frame = NSRect(origin: .zero, size: frame.size)
            hostingView.autoresizingMask = [.width, .height]
            window.contentView = hostingView
            window.makeKeyAndOrderFront(nil)
            
            restWindows.append(window)
        }
    }
    
    func closeRestWindow(playSound: Bool = false, skipped: Bool = false) {
        guard !restWindows.isEmpty else { return }
        
        if skipped {
            todaySkipCount += 1
        } else {
            todayRestCount += 1
            todayRestSeconds += restDurationSeconds
        }
        
        if playSound {
            NSSound(named: "Glass")?.play()
        }
        restSession?.invalidate()
        restSession = nil
        for window in restWindows {
            window.orderOut(nil)
        }
        restWindows.removeAll()
        countdownSeconds = workDurationMinutes * 60
        updateMenuTitle()
        startWorkTimer()
    }
    
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
    

    
    @objc func quit() {
        NSApplication.shared.terminate(nil)
    }
}

struct SettingsView: View {
    @State var workMinutes: Int
    @State var restSeconds: Int
    @State var forceRest: Bool
    @State var playSound: Bool
    @State var launchAtLogin: Bool
    @State var displayMode: Int
    let onSave: (Int, Int, Bool, Bool, Int) -> Void
    let onCancel: () -> Void
    let onLaunchAtLoginChange: (Bool) -> Bool
    
    var body: some View {
        VStack(spacing: 16) {
            Text("⚙️ 设置")
                .font(.system(size: 20, weight: .bold))
            
            // 工作时间
            VStack(alignment: .leading, spacing: 6) {
                Text("工作时间")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                HStack {
                    Slider(value: .init(
                        get: { Double(workMinutes) },
                        set: { workMinutes = Int($0) }
                    ), in: 1...60, step: 1)
                    .frame(width: 160)
                    
                    TextField("", value: $workMinutes, formatter: NumberFormatter())
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 50)
                        .multilineTextAlignment(.center)
                    
                    Text("分钟")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            }
            
            // 休息时间
            VStack(alignment: .leading, spacing: 6) {
                Text("休息时间")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                HStack {
                    Slider(value: .init(
                        get: { Double(restSeconds) },
                        set: { restSeconds = Int($0) }
                    ), in: 5...120, step: 5)
                    .frame(width: 160)
                    
                    TextField("", value: $restSeconds, formatter: NumberFormatter())
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 50)
                        .multilineTextAlignment(.center)
                    
                    Text("秒")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            }
            
            // 强制休息模式
            Toggle("强制休息模式（无法跳过）", isOn: $forceRest)
                .font(.system(size: 13))
            
            // 休息结束提示音
            Toggle("休息结束播放提示音", isOn: $playSound)
                .font(.system(size: 13))
            
            // 登录时启动
            Toggle("登录时启动", isOn: Binding(
                get: { launchAtLogin },
                set: { newValue in
                    let actualValue = onLaunchAtLoginChange(newValue)
                    launchAtLogin = actualValue
                }
            ))
            .font(.system(size: 13))
            
            // 显示模式
            VStack(alignment: .leading, spacing: 6) {
                Text("菜单栏显示")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                Picker("", selection: $displayMode) {
                    Text("图标+时间").tag(0)
                    Text("仅时间").tag(1)
                    Text("极简图标").tag(2)
                }
                .pickerStyle(.segmented)
                .frame(width: 260)
            }
            
            HStack(spacing: 12) {
                Button("取消") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
                
                Button("保存") {
                    let clampedWork = max(1, workMinutes)
                    let clampedRest = max(5, restSeconds)
                    workMinutes = clampedWork
                    restSeconds = clampedRest
                    onSave(clampedWork, clampedRest, forceRest, playSound, displayMode)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 8)
        }
        .padding(24)
        .frame(width: 320)
    }
}

struct RestView: View {
    @ObservedObject var session: RestSession
    let isForceMode: Bool
    let onSkip: () -> Void
    
    var body: some View {
        VStack(spacing: 30) {
            Text("👀 休息一下")
                .font(.system(size: 48, weight: .bold))
                .foregroundColor(.white)
            
            Text("眺望 20 米外的远方，放松眼睛")
                .font(.system(size: 24))
                .foregroundColor(.white.opacity(0.8))
            
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.2), lineWidth: 8)
                    .frame(width: 120, height: 120)
                
                Circle()
                    .trim(from: 0, to: session.progress)
                    .stroke(Color.green, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.1), value: session.progress)
                
                Text("\(session.remainingSeconds)")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.white)
            }
            
            // 强制模式下不显示跳过按钮
            if !isForceMode {
                Button("跳过休息") {
                    onSkip()
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.15))
                .cornerRadius(8)
                .foregroundColor(.white)
            } else {
                Text("强制休息中，无法跳过")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.01))
    }
}

// 当前未使用：由原生 NSMenu 替代
struct StatusMenuView: View {
    let todayRestCount: Int
    let todayRestSeconds: Int
    let todaySkipCount: Int
    let onTogglePause: () -> Void
    let onStartRest: () -> Void
    let onSettings: () -> Void
    let onQuit: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            let minutes = todayRestSeconds / 60
            let seconds = todayRestSeconds % 60
            
            VStack(alignment: .leading, spacing: 6) {
                Text("今日休息  \(todayRestCount) 次")
                Text("累计时间  \(minutes) 分 \(seconds) 秒")
                Text("跳过次数  \(todaySkipCount) 次")
            }
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            
            Divider()
            
            Button("开始/暂停", action: onTogglePause)
            Button("立即休息", action: onStartRest)
            Button("设置...", action: onSettings)
            Divider()
            Button("退出", action: onQuit)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 6)
        .frame(width: 260, alignment: .leading)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(8)
    }
}

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
    var quitMenuItem: NSMenuItem?

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
    
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if isForceRestMode && !restWindows.isEmpty {
            return .terminateCancel
        }
        return .terminateNow
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
        
        if restWindows.isEmpty && displayMode == 2 {
            dotPulseOn.toggle()
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
    
    func updateMenuTitle() {
        guard let button = statusItem.button else { return }
        
        let minutes = countdownSeconds / 60
        let seconds = countdownSeconds % 60
        let timeText = String(format: "%d:%02d", minutes, seconds)
        
        let symbolName: String
        let iconColor: NSColor
        let iconWeight: NSFont.Weight
        if !restWindows.isEmpty {
            symbolName = "figure.mind.and.body"
            iconColor = .white
            iconWeight = .regular
        } else if isPaused {
            symbolName = "pause.fill"
            iconColor = .white
            iconWeight = .semibold
        } else if countdownSeconds <= 10 {
            symbolName = "exclamationmark.triangle.fill"
            iconColor = .white
            iconWeight = .semibold
        } else if countdownSeconds < 60 {
            symbolName = "timer"
            iconColor = .white
            iconWeight = .semibold
        } else {
            symbolName = "viewfinder"
            iconColor = .white
            iconWeight = .semibold
        }
        
        switch displayMode {
        case 1: // 仅时间
            button.title = timeText
            button.image = nil
            button.imagePosition = .noImage
        case 2: // 极简图标 + 底部进度点
            button.title = ""
            button.imagePosition = .imageOnly
            button.image = renderMinimalImage(
                symbolName: symbolName,
                iconColor: iconColor,
                iconWeight: iconWeight
            )
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
    
    func renderMinimalImage(symbolName: String, iconColor: NSColor, iconWeight: NSFont.Weight) -> NSImage {
        let w: CGFloat = 28
        let h: CGFloat = 22
        
        // 所有依赖 self 的数据先算成局部常量，避免 drawing handler 捕获 self
        let isResting = !restWindows.isEmpty
        let workTotalSeconds = workDurationMinutes * 60
        let currentCountdown = countdownSeconds
        let mode = displayMode
        let paused = isPaused
        let pulseOn = dotPulseOn
        
        let activeDots: Int
        if isResting {
            activeDots = 0
        } else {
            let total = max(1, workTotalSeconds)
            let progress = CGFloat(currentCountdown) / CGFloat(total)
            activeDots = max(0, min(5, Int(ceil(progress * 5))))
        }
        let pulsingDotIndex = max(0, activeDots - 1)
        let shouldPulseDots = mode == 2 && !paused && !isResting && activeDots > 0
        
        let dotSize: CGFloat = 2.8
        let spacing: CGFloat = 1.8
        let totalWidth = dotSize * 5 + spacing * 4
        let startX = (w - totalWidth) / 2
        let dotY: CGFloat = 2.5
        
        return NSImage(size: NSSize(width: w, height: h), flipped: false) { _ in
            // 画图标（上方居中）
            if let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
                let config = NSImage.SymbolConfiguration(pointSize: 12.5, weight: iconWeight)
                    .applying(.init(hierarchicalColor: iconColor))
                let tinted = symbol.withSymbolConfiguration(config)
                let iconSize: CGFloat = 14
                let iconRect = NSRect(
                    x: (w - iconSize) / 2,
                    y: 7,
                    width: iconSize,
                    height: iconSize
                )
                tinted?.draw(in: iconRect)
            }
            
            // 底部 5 个进度点
            for index in 0..<5 {
                let isActive = index < activeDots
                let isPulsing = shouldPulseDots && index == pulsingDotIndex
                let activeAlpha: CGFloat = isPulsing ? (pulseOn ? 1.0 : 0.7) : 0.9
                
                let color = isActive
                    ? NSColor.white.withAlphaComponent(activeAlpha)
                    : NSColor.white.withAlphaComponent(0.38)
                
                let dotRect = NSRect(
                    x: startX + CGFloat(index) * (dotSize + spacing),
                    y: dotY,
                    width: dotSize,
                    height: dotSize
                )
                color.setFill()
                NSBezierPath(ovalIn: dotRect).fill()
            }
            
            return true
        }
    }
    
    @objc func togglePause() {
        if isPaused {
            isPaused = false
            startWorkTimer()
        } else {
            if let endDate = workEndDate {
                countdownSeconds = max(0, Int(ceil(endDate.timeIntervalSinceNow)))
            }
            workTimer?.invalidate()
            workTimer = nil
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
    
    func bringSettingsWindowToFront(_ window: NSWindow) {
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        window.makeKeyAndOrderFront(nil)
    }
    
    func showSettingsWindow() {
        guard settingsWindow == nil else {
            if let window = settingsWindow {
                bringSettingsWindowToFront(window)
            }
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
            onSave: { [weak self] settings in
                let defaults = UserDefaults.standard
                defaults.set(settings.workMinutes, forKey: DefaultsKey.workDurationMinutes)
                defaults.set(settings.restSeconds, forKey: DefaultsKey.restDurationSeconds)
                defaults.set(settings.forceRest, forKey: DefaultsKey.isForceRestMode)
                defaults.set(settings.playSound, forKey: DefaultsKey.playSoundOnRestEnd)
                defaults.set(settings.displayMode, forKey: DefaultsKey.displayMode)
                
                let oldWorkDuration = self?.workDurationMinutes
                let workDurationChanged = oldWorkDuration != settings.workMinutes
                
                self?.workDurationMinutes = settings.workMinutes
                self?.restDurationSeconds = settings.restSeconds
                self?.isForceRestMode = settings.forceRest
                self?.playSoundOnRestEnd = settings.playSound
                self?.displayMode = settings.displayMode
                self?.updateMenuState()
                
                if settings.displayMode == 2 {
                    self?.dotPulseOn = true
                }
                
                if workDurationChanged {
                    self?.countdownSeconds = settings.workMinutes * 60
                    if self?.isPaused == false && self?.restWindows.isEmpty == true {
                        self?.workEndDate = Date().addingTimeInterval(TimeInterval(settings.workMinutes * 60))
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
        bringSettingsWindowToFront(window)
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
            window.ignoresMouseEvents = false // 始终拦截底层点击，跳过按钮由 RestView 控制
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
        
        updateMenuState()
    }
    
    func closeRestWindow(playSound: Bool = false, skipped: Bool = false) {
        guard !restWindows.isEmpty else { return }
        
        if playSound {
            NSSound(named: "Glass")?.play()
        }
        restSession?.invalidate()
        restSession = nil
        for window in restWindows {
            window.orderOut(nil)
        }
        restWindows.removeAll()
        updateMenuState()
        countdownSeconds = workDurationMinutes * 60
        updateMenuTitle()
        if !isPaused {
            startWorkTimer()
        }
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
    

    func updateMenuState() {
        let isForceResting = isForceRestMode && !restWindows.isEmpty
        quitMenuItem?.isEnabled = !isForceResting
    }
    
    @objc func quit() {
        guard !(isForceRestMode && !restWindows.isEmpty) else { return }
        NSApplication.shared.terminate(nil)
    }
}

struct SettingsValues {
    let workMinutes: Int
    let restSeconds: Int
    let forceRest: Bool
    let playSound: Bool
    let displayMode: Int
}

struct SettingsView: View {
    @State var workMinutes: Int
    @State var restSeconds: Int
    @State var forceRest: Bool
    @State var playSound: Bool
    @State var launchAtLogin: Bool
    @State var displayMode: Int
    let onSave: (SettingsValues) -> Void
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
                        set: { workMinutes = min(max(Int($0), 1), 60) }
                    ), in: 1...60, step: 1)
                    .frame(width: 160)
                    
                    TextField("", value: .init(
                        get: { workMinutes },
                        set: { workMinutes = min(max($0, 1), 60) }
                    ), formatter: NumberFormatter())
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
                        set: { restSeconds = min(max(Int($0), 5), 120) }
                    ), in: 5...120, step: 5)
                    .frame(width: 160)
                    
                    TextField("", value: .init(
                        get: { restSeconds },
                        set: { restSeconds = min(max($0, 5), 120) }
                    ), formatter: NumberFormatter())
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
                    let clampedWork = min(max(workMinutes, 1), 60)
                    let clampedRest = min(max(restSeconds, 5), 120)
                    workMinutes = clampedWork
                    restSeconds = clampedRest
                    onSave(SettingsValues(
                        workMinutes: clampedWork,
                        restSeconds: clampedRest,
                        forceRest: forceRest,
                        playSound: playSound,
                        displayMode: displayMode
                    ))
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


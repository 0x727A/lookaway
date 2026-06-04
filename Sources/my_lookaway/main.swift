import SwiftUI
import AppKit

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
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var workTimer: Timer?
    var restWindow: NSWindow?
    var restTimer: Timer?
    var settingsWindow: NSWindow?
    var countdownSeconds = 20 * 60
    var isPaused = false
    
    // 可配置的时间
    var workDurationMinutes = 20
    var restDurationSeconds = 20
    var isForceRestMode = false
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 单实例检查
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let task = Process()
        task.launchPath = "/usr/bin/pgrep"
        task.arguments = ["-f", "my_lookaway"]
        let pipe = Pipe()
        task.standardOutput = pipe
        try? task.run()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let output = String(data: data, encoding: .utf8) {
            let pids = output.split(separator: "\n").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            if pids.contains(where: { $0 != currentPID }) {
                NSApp.terminate(nil)
                return
            }
        }
        
        NSApp.setActivationPolicy(.accessory)
        
        statusItem = NSStatusBar.system.statusItem(withLength: 44)
        
        // 左键点击弹出设置，右键弹出菜单
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem.button?.action = #selector(statusBarButtonClicked(_:))
        statusItem.button?.target = self
        
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "开始/暂停", action: #selector(togglePause), keyEquivalent: "s"))
        menu.addItem(NSMenuItem(title: "立即休息", action: #selector(startRestNow), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "设置", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
        
        // 默认隐藏菜单，由我们自己控制显示时机
        statusItem.menu?.autoenablesItems = true
        
        updateMenuTitle()
        startWorkTimer()
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    @objc func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent!
        if event.type == .rightMouseUp {
            statusItem.menu?.autoenablesItems = true
            statusItem.button?.performClick(nil)
        } else {
            // 左键点击：弹出设置窗口
            showSettingsWindow()
        }
    }
    
    func startWorkTimer() {
        workTimer?.invalidate()
        workTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }
    
    func tick() {
        guard !isPaused else { return }
        
        countdownSeconds -= 1
        if countdownSeconds <= 0 {
            countdownSeconds = workDurationMinutes * 60
            showRestWindow()
        }
        updateMenuTitle()
    }
    
    func updateMenuTitle() {
        let minutes = countdownSeconds / 60
        let seconds = countdownSeconds % 60
        let timeText = String(format: "%d:%02d", minutes, seconds)
        
        // 动态选择 SF Symbol 图标
        let symbolName: String
        let iconColor: NSColor
        
        if restWindow != nil {
            symbolName = "cup.and.saucer.fill"
            iconColor = .systemOrange
        } else if isPaused {
            symbolName = "pause.fill"
            iconColor = .systemYellow
        } else if countdownSeconds < 60 {
            symbolName = "exclamationmark.triangle.fill"
            iconColor = .systemRed
        } else {
            symbolName = "sunglasses.fill"
            iconColor = .controlTextColor
        }
        
        guard let button = statusItem.button else { return }
        
        // 清理之前的自定义 view
        button.subviews.forEach { $0.removeFromSuperview() }
        button.title = ""
        button.image = nil
        button.attributedTitle = NSAttributedString(string: "")
        
        let w: CGFloat = 44
        let h = button.bounds.height > 0 ? button.bounds.height : 24
        
        // 创建容器 view
        let container = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        container.autoresizingMask = [.width, .height]
        
        // 时间标签（第一行，偏上，y = h - 14 避免顶部被裁）
        let timeLabel = NSTextField(labelWithString: timeText)
        timeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        timeLabel.textColor = .controlTextColor
        timeLabel.alignment = .center
        timeLabel.frame = NSRect(x: 0, y: h - 14, width: w, height: 12)
        container.addSubview(timeLabel)
        
        // 图标（第二行，偏下，13×13 居中）
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
                .applying(.init(hierarchicalColor: iconColor))
            let tintedImage = image.withSymbolConfiguration(config)
            
            let iconView = NSImageView()
            iconView.image = tintedImage
            iconView.imageScaling = .scaleProportionallyDown
            let iconSize: CGFloat = 13
            iconView.frame = NSRect(
                x: (w - iconSize) / 2,
                y: 0,
                width: iconSize,
                height: iconSize
            )
            container.addSubview(iconView)
        }
        
        button.addSubview(container)
    }
    
    @objc func togglePause() {
        isPaused.toggle()
        updateMenuTitle()
    }
    
    @objc func startRestNow() {
        countdownSeconds = 0
        tick()
    }
    
    @objc func showSettings() {
        showSettingsWindow()
    }
    
    func showSettingsWindow() {
        guard settingsWindow == nil else {
            settingsWindow?.makeKeyAndOrderFront(nil)
            return
        }
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "设置"
        window.level = .floating
        window.center()
        
        let hostingView = NSHostingView(rootView: SettingsView(
            workMinutes: workDurationMinutes,
            restSeconds: restDurationSeconds,
            forceRest: isForceRestMode,
            onSave: { [weak self] work, rest, force in
                self?.workDurationMinutes = work
                self?.restDurationSeconds = rest
                self?.isForceRestMode = force
                self?.countdownSeconds = work * 60
                self?.updateMenuTitle()
                self?.settingsWindow?.orderOut(nil)
                self?.settingsWindow = nil
            },
            onCancel: { [weak self] in
                self?.settingsWindow?.orderOut(nil)
                self?.settingsWindow = nil
            }
        ))
        window.contentView = hostingView
        
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func showRestWindow() {
        guard restWindow == nil else { return }
        
        workTimer?.invalidate()
        workTimer = nil
        
        let screen = NSScreen.main!
        let frame = screen.frame
        
        restWindow = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        restWindow?.level = .screenSaver
        restWindow?.backgroundColor = isForceRestMode ? .black : NSColor.black.withAlphaComponent(0.85)
        restWindow?.isOpaque = false
        // 强制模式下忽略鼠标事件，无法点击跳过
        restWindow?.ignoresMouseEvents = isForceRestMode
        restWindow?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        let hostingView = NSHostingView(rootView: RestView(
            restSeconds: restDurationSeconds,
            isForceMode: isForceRestMode,
            onSkip: { [weak self] in
                self?.closeRestWindow()
            }
        ))
        hostingView.frame = frame
        restWindow?.contentView = hostingView
        restWindow?.makeKeyAndOrderFront(nil)
        
        let startTime = Date()
        restTimer?.invalidate()
        restTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                let elapsed = Date().timeIntervalSince(startTime)
                let remaining = max(0, (self?.restDurationSeconds ?? 20) - Int(elapsed))
                if remaining <= 0 {
                    self?.closeRestWindow()
                }
            }
        }
    }
    
    func closeRestWindow() {
        restTimer?.invalidate()
        restTimer = nil
        restWindow?.orderOut(nil)
        restWindow = nil
        countdownSeconds = workDurationMinutes * 60
        updateMenuTitle()
        startWorkTimer()
    }
    
    @objc func quit() {
        NSApplication.shared.terminate(nil)
    }
}

struct SettingsView: View {
    @State var workMinutes: Int
    @State var restSeconds: Int
    @State var forceRest: Bool
    let onSave: (Int, Int, Bool) -> Void
    let onCancel: () -> Void
    
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
            
            HStack(spacing: 12) {
                Button("取消") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
                
                Button("保存") {
                    onSave(workMinutes, restSeconds, forceRest)
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
    let restSeconds: Int
    let isForceMode: Bool
    let onSkip: () -> Void
    @State private var progress: CGFloat = 1.0
    @State private var remainingText = ""
    
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
                    .trim(from: 0, to: progress)
                    .stroke(Color.green, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: progress)
                
                Text(remainingText)
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
        .onAppear {
            remainingText = String(restSeconds)
            let startTime = Date()
            var timer: Timer?
            timer = Timer(timeInterval: 0.1, repeats: true) { _ in
                Task { @MainActor in
                    let elapsed = Date().timeIntervalSince(startTime)
                    let seconds = max(0, restSeconds - Int(elapsed))
                    progress = CGFloat(seconds) / CGFloat(restSeconds)
                    remainingText = String(seconds)
                    if seconds <= 0 {
                        timer?.invalidate()
                        timer = nil
                    }
                }
            }
            RunLoop.current.add(timer!, forMode: .common)
        }
    }
}

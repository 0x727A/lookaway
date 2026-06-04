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
    var countdownSeconds = 20 * 60
    var isPaused = false
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 单实例检查：如果已有同名进程在运行，直接退出
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
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "20:00"
        
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "开始/暂停", action: #selector(togglePause), keyEquivalent: "s"))
        menu.addItem(NSMenuItem(title: "立即休息", action: #selector(startRestNow), keyEquivalent: "r"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
        
        startWorkTimer()
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
            countdownSeconds = 20 * 60
            showRestWindow()
        }
        updateMenuTitle()
    }
    
    func updateMenuTitle() {
        let minutes = countdownSeconds / 60
        let seconds = countdownSeconds % 60
        statusItem.button?.title = String(format: "%d:%02d", minutes, seconds)
    }
    
    @objc func togglePause() {
        isPaused.toggle()
        if isPaused {
            statusItem.button?.title = "⏸ " + (statusItem.button?.title ?? "")
        } else {
            statusItem.button?.title = (statusItem.button?.title ?? "").replacingOccurrences(of: "⏸ ", with: "")
        }
    }
    
    @objc func startRestNow() {
        countdownSeconds = 0
        tick()
    }
    
    func showRestWindow() {
        guard restWindow == nil else { return }
        
        // 暂停工作计时器
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
        restWindow?.backgroundColor = NSColor.black.withAlphaComponent(0.85)
        restWindow?.isOpaque = false
        restWindow?.ignoresMouseEvents = false
        restWindow?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        let hostingView = NSHostingView(rootView: RestView(onSkip: { [weak self] in
            self?.closeRestWindow()
        }))
        hostingView.frame = frame
        restWindow?.contentView = hostingView
        restWindow?.makeKeyAndOrderFront(nil)
        
        let startTime = Date()
        restTimer?.invalidate()
        restTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                let elapsed = Date().timeIntervalSince(startTime)
                let remaining = max(0, 20 - Int(elapsed))
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
        // 重置工作倒计时并开始新一轮
        countdownSeconds = 20 * 60
        updateMenuTitle()
        startWorkTimer()
    }
    
    @objc func quit() {
        NSApplication.shared.terminate(nil)
    }
}

struct RestView: View {
    let onSkip: () -> Void
    @State private var progress: CGFloat = 1.0
    @State private var remainingText = "20"
    
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
            
            Button("跳过休息") {
                onSkip()
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.15))
            .cornerRadius(8)
            .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.01))
        .onAppear {
            let startTime = Date()
            var timer: Timer?
            timer = Timer(timeInterval: 0.1, repeats: true) { _ in
                Task { @MainActor in
                    let elapsed = Date().timeIntervalSince(startTime)
                    let seconds = max(0, 20 - Int(elapsed))
                    progress = CGFloat(seconds) / 20.0
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

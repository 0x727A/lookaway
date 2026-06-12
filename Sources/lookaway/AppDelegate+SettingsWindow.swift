import AppKit
import SwiftUI

extension AppDelegate {
    @objc func showSettings() {
        guard !pendingShowSettings else { return }
        pendingShowSettings = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.pendingShowSettings = false
            self?.showSettingsWindow()
        }
    }

    /// 将设置窗口激活并带到最前面
    /// macOS 从状态栏 Extra 菜单打开普通窗口时，首帧同步 activate 可能会被系统的焦点防夺取机制忽略。
    /// 在下一帧（DispatchQueue.main.async）再次触发激活，确保窗口稳定呈现在最前面并获取输入焦点。
    func bringSettingsWindowToFront(_ window: NSWindow) {
        NSRunningApplication.current.activate(options: [
            .activateIgnoringOtherApps,
            .activateAllWindows
        ])
        window.makeKeyAndOrderFront(nil)

        DispatchQueue.main.async {
            NSRunningApplication.current.activate(options: [
                .activateIgnoringOtherApps,
                .activateAllWindows
            ])
            window.makeKeyAndOrderFront(nil)
        }
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
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 510),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "设置"
        window.level = .floating
        window.center()
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.delegate = self

        let hostingView = NSHostingView(rootView: SettingsView(
            workMinutes: workDurationMinutes,
            restSeconds: restDurationSeconds,
            forceRest: isForceRestMode,
            playSoundOnRestEnd: playSoundOnRestEnd,
            playSoundOnRestStart: playSoundOnRestStart,
            restStartSoundName: restStartSoundName,
            restEndSoundName: restEndSoundName,
            pauseVideo: pauseVideoOnRestStart,
            launchAtLogin: launchAtLogin,
            displayMode: displayMode,
            onSave: { [weak self] settings in
                let defaults = UserDefaults.standard
                defaults.set(settings.workMinutes, forKey: DefaultsKey.workDurationMinutes)
                defaults.set(settings.restSeconds, forKey: DefaultsKey.restDurationSeconds)
                defaults.set(settings.forceRest, forKey: DefaultsKey.isForceRestMode)
                defaults.set(settings.playSoundOnRestEnd, forKey: DefaultsKey.playSoundOnRestEnd)
                defaults.set(settings.playSoundOnRestStart, forKey: DefaultsKey.playSoundOnRestStart)
                defaults.set(settings.restStartSoundName, forKey: DefaultsKey.restStartSoundName)
                defaults.set(settings.restEndSoundName, forKey: DefaultsKey.restEndSoundName)
                defaults.set(settings.pauseVideo, forKey: DefaultsKey.pauseVideoOnRestStart)
                defaults.set(settings.displayMode.rawValue, forKey: DefaultsKey.displayMode)

                let oldWorkDuration = self?.workDurationMinutes
                let workDurationChanged = oldWorkDuration != settings.workMinutes

                self?.workDurationMinutes = settings.workMinutes
                self?.restDurationSeconds = settings.restSeconds
                self?.isForceRestMode = settings.forceRest
                self?.playSoundOnRestEnd = settings.playSoundOnRestEnd
                self?.playSoundOnRestStart = settings.playSoundOnRestStart
                self?.restStartSoundName = settings.restStartSoundName
                self?.restEndSoundName = settings.restEndSoundName
                self?.pauseVideoOnRestStart = settings.pauseVideo
                self?.displayMode = settings.displayMode
                self?.updateMenuState()

                if settings.displayMode == .minimalIcon {
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
}

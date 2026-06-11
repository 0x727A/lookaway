import AppKit
import SwiftUI

extension AppDelegate {
    @objc func startRestNow() {
        countdownSeconds = workDurationMinutes * 60
        workEndDate = nil
        showRestWindow()
        updateMenuTitle()
    }

    func playAlertSound(named soundName: String) {
        if NSSound(named: NSSound.Name(soundName))?.play() != true {
            NSSound(named: "Glass")?.play()
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

        let session = RestSession(duration: restDurationSeconds) { [weak self] in
            self?.closeRestWindow(playSound: self?.playSoundOnRestEnd ?? true, skipped: false)
        }
        restSession = session
        session.start()

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

        if playSoundOnRestStart {
            playAlertSound(named: restStartSoundName)
        }

        if pauseVideoOnRestStart {
            let videoTargets = VideoPauser.runningTargets()
            if !videoTargets.isEmpty {
                VideoPauser.pauseTargetsAsync(videoTargets)
            }
        }
    }

    func closeRestWindow(playSound: Bool = false, skipped: Bool = false) {
        guard !restWindows.isEmpty else { return }

        if playSound {
            playAlertSound(named: restEndSoundName)
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

        if isSystemSuspended || isSleepInactive || isScreenInactive || isSessionInactive {
            isSystemSuspended = true
            workTimer?.invalidate()
            workTimer = nil
            workEndDate = nil
            return
        }

        if !isPaused {
            startWorkTimer()
        }
    }
}

import Foundation

extension AppDelegate {
    func suspendWorkCountdownForInactiveSystem() {
        guard !isSystemSuspended else { return }

        isSystemSuspended = true
        workTimer?.invalidate()
        workTimer = nil
        workEndDate = nil
        updateMenuTitle()
    }

    func resumeWorkCountdownIfSystemActive() {
        guard isSystemSuspended else { return }
        guard !isSleepInactive && !isScreenInactive && !isSessionInactive else { return }

        isSystemSuspended = false
        guard restWindows.isEmpty else { return }

        countdownSeconds = workDurationMinutes * 60

        if isPaused {
            workEndDate = nil
            updateMenuTitle()
        } else {
            startWorkTimer()
            updateMenuTitle()
        }
    }

    @objc func systemWillSuspend() {
        isSleepInactive = true
        suspendWorkCountdownForInactiveSystem()
    }

    @objc func systemDidResume() {
        isSleepInactive = false
        resumeWorkCountdownIfSystemActive()
    }

    @objc func screenDidSleep() {
        isScreenInactive = true
        suspendWorkCountdownForInactiveSystem()
    }

    @objc func screenDidWake() {
        isScreenInactive = false
        resumeWorkCountdownIfSystemActive()
    }

    @objc func sessionDidResignActive() {
        isSessionInactive = true
        suspendWorkCountdownForInactiveSystem()
    }

    @objc func sessionDidBecomeActive() {
        isSessionInactive = false
        resumeWorkCountdownIfSystemActive()
    }

    @objc func screenIsLocked() {
        NSLog("LookAway 收到锁屏通知")
        isSessionInactive = true
        suspendWorkCountdownForInactiveSystem()
    }

    @objc func screenIsUnlocked() {
        NSLog("LookAway 收到解锁通知")
        isSessionInactive = false
        resumeWorkCountdownIfSystemActive()
    }
}

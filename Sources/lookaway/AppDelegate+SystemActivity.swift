import Foundation

extension AppDelegate {
    func suspendWorkCountdownForInactiveSystem() {
        guard !isSystemSuspended else { return }

        isSystemSuspended = true
        suspendDate = Date()
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

        if let sDate = suspendDate {
            let inactiveDuration = Date().timeIntervalSince(sDate)
            if inactiveDuration >= Double(restDurationSeconds) {
                // 挂起时间大于等于要求的休息时长，判定已完成休息，重置倒计时
                countdownSeconds = workDurationMinutes * 60
            } else {
                // 挂起时间不足，判定为误触或短暂锁屏，恢复挂起前的倒计时
            }
            suspendDate = nil
        } else {
            // 没有记录到时间戳，默认安全重置
            countdownSeconds = workDurationMinutes * 60
        }

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

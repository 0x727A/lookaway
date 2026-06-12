import Foundation

extension AppDelegate {
    func startWorkTimer() {
        guard !isSystemSuspended else { return }
        workTimer?.invalidate()
        workEndDate = Date().addingTimeInterval(TimeInterval(countdownSeconds))

        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        workTimer = timer
        // Timer 已注册到 RunLoop.main；使用 assumeIsolated 时必须保持在此主运行循环上，切勿换到其他队列。
        RunLoop.main.add(timer, forMode: .common)
    }

    func tick() {
        guard !isPaused && !isSystemSuspended else { return }
        guard let endDate = workEndDate else { return }

        countdownSeconds = max(0, Int(ceil(endDate.timeIntervalSinceNow)))

        if countdownSeconds <= 0 {
            countdownSeconds = workDurationMinutes * 60
            workEndDate = nil
            showRestWindow()
            return
        }

        if restWindows.isEmpty && currentDisplayMode == .minimalIcon {
            dotPulseOn.toggle()
        }

        updateMenuTitle()
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
}

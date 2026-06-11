import AppKit

extension AppDelegate {
    func applyStatusItemLength() {
        switch currentDisplayMode {
        case .timeOnly:
            statusItem.length = 46
        case .minimalIcon:
            statusItem.length = 28
        case .iconAndTime:
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

        switch currentDisplayMode {
        case .timeOnly: // 仅时间
            button.title = timeText
            button.image = nil
            button.imagePosition = .noImage
        case .minimalIcon: // 极简图标 + 底部进度点
            button.title = ""
            button.imagePosition = .imageOnly
            button.image = renderMinimalImage(
                symbolName: symbolName,
                iconColor: iconColor,
                iconWeight: iconWeight
            )
        case .iconAndTime: // 图标+时间
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
        let mode = currentDisplayMode
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
        let shouldPulseDots = mode == .minimalIcon && !paused && !isResting && activeDots > 0

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

    func updateMenuState() {
        let isForceResting = isForceRestMode && !restWindows.isEmpty
        quitMenuItem?.isEnabled = !isForceResting
    }
}

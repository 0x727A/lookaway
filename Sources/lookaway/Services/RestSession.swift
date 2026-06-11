import Foundation
import Combine

@MainActor
final class RestSession: ObservableObject {
    @Published var remainingSeconds: Int
    @Published var progress: CGFloat = 1

    private let duration: Int
    private let startTime = Date()
    private var timer: Timer?
    private let onComplete: () -> Void
    private var isCompleted = false

    init(duration: Int, onComplete: @escaping () -> Void) {
        let safeDuration = max(1, duration)
        self.duration = safeDuration
        self.remainingSeconds = safeDuration
        self.onComplete = onComplete
    }

    func start() {
        timer?.invalidate()
        timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        // Timer 已注册到 RunLoop.main；使用 assumeIsolated 时必须保持在此主运行循环上，切勿换到其他队列。
        RunLoop.main.add(timer!, forMode: .common)
    }

    func tick() {
        guard !isCompleted else { return }

        let elapsed = Date().timeIntervalSince(startTime)
        let remaining = max(0, Double(duration) - elapsed)

        remainingSeconds = Int(ceil(remaining))
        progress = CGFloat(remaining / Double(duration))

        if remaining <= 0 {
            isCompleted = true
            progress = 0
            remainingSeconds = 0
            timer?.invalidate()
            timer = nil
            onComplete()
        }
    }

    func invalidate() {
        isCompleted = true
        timer?.invalidate()
        timer = nil
    }
}

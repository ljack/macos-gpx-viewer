import SwiftUI

@MainActor
@Observable
final class Playback {
    var elapsed: TimeInterval = 0
    var isPlaying = false
    var rate: Double = 30
    var flyover = true
    var showMoments = true
    let duration: TimeInterval

    static let rates: [Double] = [10, 30, 60, 120]

    private var ticker: Task<Void, Never>?

    init(duration: TimeInterval) {
        self.duration = duration
    }

    var fraction: Double { duration > 0 ? elapsed / duration : 0 }
    var atEnd: Bool { elapsed >= duration - 0.001 }

    func toggle() {
        isPlaying ? pause() : play()
    }

    func play() {
        guard duration > 0 else { return }
        if atEnd { elapsed = 0 }
        isPlaying = true
        ticker?.cancel()
        ticker = Task { [weak self] in
            var last = ContinuousClock.now
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(33))
                guard let self, !Task.isCancelled else { return }
                let now = ContinuousClock.now
                let dt = Double((now - last).components.attoseconds) / 1e18 + Double((now - last).components.seconds)
                last = now
                let next = elapsed + dt * rate
                if next >= duration {
                    elapsed = duration
                    pause()
                    return
                }
                elapsed = next
            }
        }
    }

    func pause() {
        isPlaying = false
        ticker?.cancel()
        ticker = nil
    }

    func seek(_ t: TimeInterval) {
        elapsed = min(max(t, 0), duration)
    }

    func skip(_ delta: TimeInterval) {
        seek(elapsed + delta)
    }
}

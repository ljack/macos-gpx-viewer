import AppKit
import QuartzCore

@MainActor
@Observable
final class Playback: NSObject {
    var elapsed: TimeInterval = 0 {
        didSet { elapsedHandler?(elapsed) }
    }
    /// Synchronous per-change hook for imperative consumers (the map stage) that must not go through SwiftUI diffing.
    @ObservationIgnored var elapsedHandler: ((TimeInterval) -> Void)?
    var isPlaying = false
    var rate: Double = 30
    var flyover = true
    var showMoments = true
    let duration: TimeInterval

    static let rates: [Double] = [10, 30, 60, 120]

    @ObservationIgnored private var link: CADisplayLink?
    @ObservationIgnored private var lastTimestamp: CFTimeInterval?

    init(duration: TimeInterval) {
        self.duration = duration
        super.init()
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
        link?.invalidate()
        lastTimestamp = nil
        // Display-synchronised ticks: one update per presented frame, so motion is even.
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let link = screen.displayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func tick(_ link: CADisplayLink) {
        MainActor.assumeIsolated {
            defer { lastTimestamp = link.targetTimestamp }
            guard let last = lastTimestamp else { return }
            let dt = min(max(link.targetTimestamp - last, 0), 0.1)
            let next = elapsed + dt * rate
            if next >= duration {
                elapsed = duration
                pause()
            } else {
                elapsed = next
            }
        }
    }

    func pause() {
        isPlaying = false
        link?.invalidate()
        link = nil
        lastTimestamp = nil
    }

    func seek(_ t: TimeInterval) {
        elapsed = min(max(t, 0), duration)
    }

    func skip(_ delta: TimeInterval) {
        seek(elapsed + delta)
    }
}

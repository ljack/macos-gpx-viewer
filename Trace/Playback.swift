import AppKit
import QuartzCore

@MainActor
@Observable
final class Playback: NSObject {
    /// Coarse playhead for SwiftUI. Published at most `publishHz` times per second during playback
    /// (and immediately on seek / pause), so the chart, readout and cards are not re-laid out every frame.
    private(set) var elapsed: TimeInterval = 0
    var isPlaying = false
    var rate: Double = 30
    var flyover = true
    var showMoments = true
    let duration: TimeInterval

    /// Fine-grained playhead, updated every frame. Not observed; consumed through `timeHandler`.
    @ObservationIgnored private(set) var time: TimeInterval = 0 {
        didSet { timeHandler?(time) }
    }
    /// Synchronous per-frame hook for imperative consumers (the map stage) that bypass SwiftUI diffing.
    @ObservationIgnored var timeHandler: ((TimeInterval) -> Void)?

    static let rates: [Double] = [10, 30, 60, 120]
    /// How often the coarse playhead reaches SwiftUI while playing.
    @ObservationIgnored private let publishInterval: CFTimeInterval = 1 / 10

    @ObservationIgnored private var link: CADisplayLink?
    @ObservationIgnored private var lastTimestamp: CFTimeInterval?
    @ObservationIgnored private var lastPublish: CFTimeInterval = 0

    init(duration: TimeInterval) {
        self.duration = duration
        super.init()
    }

    var fraction: Double { duration > 0 ? time / duration : 0 }
    var atEnd: Bool { time >= duration - 0.001 }

    func toggle() {
        isPlaying ? pause() : play()
    }

    func play() {
        guard duration > 0 else { return }
        if atEnd { set(0) }
        isPlaying = true
        link?.invalidate()
        lastTimestamp = nil
        // Display-synchronised ticks: one update per presented frame, so motion is even.
        let screen = NSApp.keyWindow?.screen ?? NSScreen.main ?? NSScreen.screens[0]
        let link = screen.displayLink(target: self, selector: #selector(tick(_:)))
        // Playback CPU is almost entirely MapKit rendering the moving 3D scene, so frame rate is the one
        // lever that matters: honour Low Power Mode with 30 fps, otherwise ask for the display's native rate.
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let native = Float(min(screen.maximumFramesPerSecond, 120))
        link.preferredFrameRateRange = lowPower
            ? CAFrameRateRange(minimum: 24, maximum: 30, preferred: 30)
            : CAFrameRateRange(minimum: 30, maximum: native, preferred: native)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func tick(_ link: CADisplayLink) {
        MainActor.assumeIsolated {
            defer { lastTimestamp = link.targetTimestamp }
            guard let last = lastTimestamp else { return }
            let dt = min(max(link.targetTimestamp - last, 0), 0.1)
            let next = time + dt * rate
            if next >= duration {
                set(duration)
                pause()
                return
            }
            time = next
            if link.targetTimestamp - lastPublish >= publishInterval {
                lastPublish = link.targetTimestamp
                elapsed = time
            }
        }
    }

    func pause() {
        isPlaying = false
        link?.invalidate()
        link = nil
        lastTimestamp = nil
        elapsed = time
    }

    func seek(_ t: TimeInterval) {
        set(min(max(t, 0), duration))
    }

    func skip(_ delta: TimeInterval) {
        seek(time + delta)
    }

    private func set(_ t: TimeInterval) {
        time = t
        elapsed = t
        lastPublish = CACurrentMediaTime()
    }
}

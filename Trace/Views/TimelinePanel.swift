import SwiftUI
import Charts

struct TimelinePanel: View {
    let track: Track
    @Bindable var playback: Playback

    struct Bin: Identifiable {
        let id: Int
        let t: Double
        let speed: Double
    }

    private let bins: [Bin]
    private let fill: LinearGradient
    private let line: LinearGradient
    @State private var plot: CGRect = .zero

    init(track: Track, playback: Playback) {
        self.track = track
        self.playback = playback
        let b = Self.makeBins(track)
        bins = b
        fill = Self.speedGradient(track, b, opacity: 0.45)
        line = Self.speedGradient(track, b, opacity: 1)
    }

    private static func makeBins(_ track: Track) -> [Bin] {
        let s = track.samples
        guard s.count > 1 else { return [] }
        let target = 360
        let step = max(1, s.count / target)
        var out: [Bin] = []
        var i = 0
        while i < s.count {
            let slice = s[i..<min(i + step, s.count)]
            let speed = slice.map(\.speed).max() ?? 0
            out.append(Bin(id: i, t: slice.first!.t, speed: speed))
            i += step
        }
        if let last = s.last, out.last?.t != last.t { out.append(Bin(id: s.count, t: last.t, speed: last.speed)) }
        return out
    }

    var body: some View {
        HStack(spacing: 18) {
            transport
            ZStack {
                StaticSpeedChart(track: track, bins: bins, fill: fill, line: line, axisValues: axisValues) { axisLabel($0) }
                    .equatable()
                PlayheadOverlay(track: track, playback: playback, plot: plot)
            }
            .onPreferenceChange(PlotFrameKey.self) { plot = $0 }
            .frame(height: 78)
            Readout(track: track, playback: playback)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
    }

    private var transport: some View {
        HStack(spacing: 6) {
            Button {
                playback.toggle()
            } label: {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(.circle)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .help(playback.isPlaying ? "Pause" : "Play")

            Menu {
                ForEach(Playback.rates, id: \.self) { r in
                    Button {
                        playback.rate = r
                    } label: {
                        if playback.rate == r { Label("\(Int(r))×", systemImage: "checkmark") } else { Text("\(Int(r))×") }
                    }
                }
            } label: {
                Text("\(Int(playback.rate))×")
                    .font(.callout.weight(.medium).monospacedDigit())
                    .frame(width: 44)
            }
            .menuStyle(.button)
            .buttonStyle(.glass)
            .fixedSize()
            .help("Playback speed")
        }
    }

    private static func speedGradient(_ track: Track, _ data: [Bin], opacity: Double) -> LinearGradient {
        let d = max(track.duration, 1)
        let stops = data.map { bin in
            Gradient.Stop(color: SpeedPalette.color(track.speedFraction(bin.speed)).opacity(opacity), location: bin.t / d)
        }
        return LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing)
    }

    private var axisValues: [Double] {
        let d = track.duration
        guard d > 0 else { return [0] }
        let candidates: [Double] = track.hasTime ? [60, 300, 600, 900, 1800, 3600, 7200, 14400] : [30, 60, 120, 300, 600]
        let stride = candidates.first { d / $0 <= 8 } ?? candidates.last!
        return Array(Swift.stride(from: 0, through: d, by: stride))
    }

    private func axisLabel(_ t: Double) -> String {
        if let start = track.startDate { return Format.timeOfDay(start.addingTimeInterval(t)) }
        return Format.distance(track.sample(at: t).distance)
    }

}

/// Live numbers at the playhead. Separate view so only it re-renders per frame.
private struct Readout: View {
    let track: Track
    @Bindable var playback: Playback

    var body: some View {
        let s = track.sample(at: playback.elapsed)
        return VStack(alignment: .trailing, spacing: 2) {
            if let start = track.startDate {
                Text(Format.timeOfDay(start.addingTimeInterval(s.t)))
                    .font(.system(size: 26, weight: .semibold, design: .rounded).monospacedDigit())
                Text(Format.clock(s.t))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                Text(Format.distance(s.distance))
                    .font(.system(size: 26, weight: .semibold, design: .rounded).monospacedDigit())
            }
            HStack(spacing: 6) {
                Text(Format.distance(s.distance))
                if track.hasTime {
                    Circle().fill(SpeedPalette.color(track.speedFraction(s.speed))).frame(width: 7, height: 7)
                    Text(Format.speed(s.speed))
                }
            }
            .font(.callout.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .frame(width: 150, alignment: .trailing)
        .contentTransition(.numericText())
    }
}

/// The chart itself never depends on the playhead, so it is only rebuilt when the window resizes.
private struct StaticSpeedChart: View, Equatable {
    let track: Track
    let bins: [TimelinePanel.Bin]
    let fill: LinearGradient
    let line: LinearGradient
    let axisValues: [Double]
    let axisLabel: (Double) -> String

    static func == (a: Self, b: Self) -> Bool { a.bins.count == b.bins.count && a.track.duration == b.track.duration }

    var body: some View {
        Chart {
            ForEach(bins) { bin in
                AreaMark(x: .value("Time", bin.t), y: .value("Speed", bin.speed))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(fill)
                LineMark(x: .value("Time", bin.t), y: .value("Speed", bin.speed))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                    .foregroundStyle(line)
            }
        }
        .chartXScale(domain: 0...max(track.duration, 1))
        .chartYScale(domain: 0...max(track.stats.maxSpeed * 1.08, 1))
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: axisValues) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(.secondary.opacity(0.3))
                AxisValueLabel {
                    if let t = value.as(Double.self) {
                        Text(axisLabel(t)).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Color.clear.preference(key: PlotFrameKey.self, value: geo[proxy.plotFrame!])
            }
        }
    }
}

private struct PlotFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

/// Playhead line + dot, positioned in the chart's plot frame. Cheap to redraw every frame.
private struct PlayheadOverlay: View {
    let track: Track
    @Bindable var playback: Playback
    let plot: CGRect

    var body: some View {
        let sample = track.sample(at: playback.elapsed)
        let fx = track.duration > 0 ? playback.elapsed / track.duration : 0
        let yMax = max(track.stats.maxSpeed * 1.08, 1)
        let x = plot.minX + plot.width * fx
        let y = plot.maxY - plot.height * min(sample.speed / yMax, 1)
        ZStack(alignment: .topLeading) {
            Color.clear
            Rectangle()
                .fill(.primary.opacity(0.8))
                .frame(width: 1.5, height: plot.height)
                .offset(x: x - 0.75, y: plot.minY)
            Circle()
                .fill(SpeedPalette.color(track.speedFraction(sample.speed)))
                .frame(width: 8, height: 8)
                .overlay(Circle().stroke(.white, lineWidth: 2))
                .offset(x: x - 4, y: y - 4)
        }
        .contentShape(.rect)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { g in
                    guard plot.width > 0 else { return }
                    let f = min(max((g.location.x - plot.minX) / plot.width, 0), 1)
                    playback.pause()
                    playback.seek(track.duration * f)
                })
    }
}

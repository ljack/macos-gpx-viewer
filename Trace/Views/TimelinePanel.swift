import SwiftUI
import Charts

struct TimelinePanel: View {
    let track: Track
    @Bindable var playback: Playback

    private struct Bin: Identifiable {
        let id: Int
        let t: Double
        let speed: Double
    }

    private var bins: [Bin] {
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

    private var current: Sample { track.sample(at: playback.elapsed) }

    var body: some View {
        HStack(spacing: 18) {
            transport
            chart
                .frame(height: 78)
            readout
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

    private var chart: some View {
        let playhead = playback.elapsed
        let live = current
        let data = bins
        let fill = speedGradient(data, opacity: 0.45)
        let line = speedGradient(data, opacity: 1)
        return Chart {
            ForEach(data) { bin in
                AreaMark(x: .value("Time", bin.t), y: .value("Speed", bin.speed))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(fill)
                LineMark(x: .value("Time", bin.t), y: .value("Speed", bin.speed))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                    .foregroundStyle(line)
            }
            RuleMark(x: .value("Now", playhead))
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .foregroundStyle(.primary.opacity(0.8))
            PointMark(x: .value("Now", playhead), y: .value("Speed", live.speed))
                .symbolSize(90)
                .foregroundStyle(.white)
            PointMark(x: .value("Now", playhead), y: .value("Speed", live.speed))
                .symbolSize(40)
                .foregroundStyle(SpeedPalette.color(track.speedFraction(live.speed)))
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
                Rectangle()
                    .fill(.clear)
                    .contentShape(.rect)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { g in
                                guard let plot = proxy.plotFrame else { return }
                                let x = g.location.x - geo[plot].origin.x
                                if let t: Double = proxy.value(atX: x) {
                                    playback.pause()
                                    playback.seek(t)
                                }
                            })
            }
        }
    }

    private func speedGradient(_ data: [Bin], opacity: Double) -> LinearGradient {
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

    private var readout: some View {
        let s = current
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

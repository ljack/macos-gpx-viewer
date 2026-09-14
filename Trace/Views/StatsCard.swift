import SwiftUI

struct StatsCard: View {
    let track: Track

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(track.name)
                    .font(.title2.weight(.semibold))
                    .lineLimit(2)
                if let line = Format.dateLine(start: track.startDate, end: track.endDate) {
                    Text(line)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
                GridRow {
                    Stat("Distance", Format.distance(track.stats.distance))
                    if track.hasTime {
                        Stat("Duration", Format.duration(track.stats.duration))
                    }
                }
                if track.hasTime {
                    GridRow {
                        Stat("Moving", Format.duration(track.stats.movingTime))
                        Stat("Avg speed", Format.speed(track.stats.averageMovingSpeed))
                    }
                    GridRow {
                        Stat("Top speed", Format.speed(track.stats.maxSpeed))
                        if let gain = track.stats.elevationGain {
                            Stat("Climb", Format.elevation(gain))
                        }
                    }
                } else if let gain = track.stats.elevationGain {
                    GridRow { Stat("Climb", Format.elevation(gain)) }
                }
            }

            if track.hasTime {
                VStack(alignment: .leading, spacing: 5) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(SpeedPalette.gradient)
                        .frame(height: 6)
                    HStack {
                        Text(Format.speed(track.stats.speedFloor))
                        Spacer()
                        Text(Format.speed(track.stats.speedCeiling))
                    }
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(18)
        .frame(width: 290, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    private struct Stat: View {
        let label: String
        let value: String
        init(_ label: String, _ value: String) { self.label = label; self.value = value }
        var body: some View {
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title3.weight(.semibold).monospacedDigit())
            }
            .frame(minWidth: 108, alignment: .leading)
        }
    }
}

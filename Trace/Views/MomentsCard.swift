import SwiftUI

struct MomentsCard: View {
    let track: Track
    @Bindable var playback: Playback

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Moments")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 8)
            ScrollView {
              VStack(alignment: .leading, spacing: 0) {
              ForEach(track.moments) { moment in
                Button {
                    playback.pause()
                    withAnimation(.snappy) { playback.seek(moment.t) }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: moment.symbol)
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 26, height: 26)
                            .background(tint(moment.kind).gradient, in: .circle)
                            .foregroundStyle(.white)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(moment.title).font(.body)
                            if !moment.detail.isEmpty {
                                Text(moment.detail).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 8)
                        Text(clock(moment.t))
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
              }
              }
            }
            .frame(maxHeight: 440)
            Spacer().frame(height: 8)
        }
        .frame(width: 270, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    private func clock(_ t: TimeInterval) -> String {
        if let start = track.startDate { return Format.timeOfDay(start.addingTimeInterval(t)) }
        return Format.distance(track.sample(at: t).distance)
    }

    static func tint(_ kind: Moment.Kind) -> Color {
        switch kind {
        case .start: .green
        case .finish: .primary
        case .stop: .gray
        case .fastestKilometre: .orange
        case .topSpeed: .red
        case .turnaround: .indigo
        }
    }

    private func tint(_ kind: Moment.Kind) -> Color { Self.tint(kind) }
}

import SwiftUI
import MapKit

enum MapFlavor: String, CaseIterable, Identifiable {
    case standard, hybrid, satellite
    var id: String { rawValue }
    var label: String {
        switch self { case .standard: "Map"; case .hybrid: "Hybrid"; case .satellite: "Satellite" }
    }
    var symbol: String {
        switch self { case .standard: "map"; case .hybrid: "map.fill"; case .satellite: "globe.europe.africa.fill" }
    }
}

/// Window-level shell. Its body must not read `playback.elapsed`: everything that moves per frame
/// lives in `MapStage`, `PlayheadOverlay` and `Readout`, so the toolbar and cards are never re-laid out
/// during playback.
struct TrackView: View {
    let track: Track
    @State private var playback: Playback
    @State private var flavor: MapFlavor = .standard
    @State private var showDefaultOffer = DefaultHandler.shouldOffer
    @State private var madeDefault = false
    @State private var showStats = true
    @State private var showMomentsCard = true
    @State private var fitRequest = 0

    init(track: Track) {
        self.track = track
        _playback = State(initialValue: Playback(duration: track.duration))
    }

    var body: some View {
        ZStack {
            MapStage(track: track, playback: playback, flavor: flavor, showMoments: playback.showMoments,
                     fitRequest: fitRequest) { t in
                playback.pause()
                playback.seek(t)
            }
            .ignoresSafeArea()
            overlays
        }
        .toolbar { toolbar }
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .onAppear {
            registerCommands()
            if let mode = ProcessInfo.processInfo.environment["TRACE_APPEARANCE"] {
                NSApp.appearance = NSAppearance(named: mode == "dark" ? .darkAqua : .aqua)
            }
            if ProcessInfo.processInfo.environment["TRACE_FLYOVER"] == "0" { playback.flyover = false }
            if let raw = ProcessInfo.processInfo.environment["TRACE_SEEK"], let f = Double(raw) {
                playback.seek(track.duration * f)
            }
            if let raw = ProcessInfo.processInfo.environment["TRACE_AUTOPLAY"], let f = Double(raw) {
                playback.seek(track.duration * f)
                playback.play()
            }
        }
        .frame(minWidth: 900, minHeight: 600)
    }

    private func fit() { fitRequest += 1 }

    private func registerCommands() {
        let c = PlaybackCommands.shared
        c.togglePlay = { playback.toggle() }
        c.skip = { playback.pause(); playback.skip($0) }
        c.seekFraction = { playback.pause(); playback.seek(track.duration * $0) }
        c.toggleFlyover = { playback.flyover.toggle() }
    }

    // MARK: - Overlays

    private var overlays: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                if showStats {
                    StatsCard(track: track)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 12) {
                    if showDefaultOffer { defaultOffer }
                    if showMomentsCard {
                        MomentsCard(track: track, playback: playback)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
            }
            .padding(20)
            Spacer()
            TimelinePanel(track: track, playback: playback)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
        }
        .animation(.snappy, value: showStats)
        .animation(.snappy, value: showMomentsCard)
        .animation(.snappy, value: showDefaultOffer)
    }

    private var defaultOffer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: madeDefault ? "checkmark.circle.fill" : "doc.badge.gearshape")
                    .font(.title2)
                    .foregroundStyle(madeDefault ? .green : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(madeDefault ? "Trace now opens GPX files" : "Open GPX files with Trace?")
                        .font(.callout.weight(.semibold))
                    if !madeDefault {
                        Text("Double-click any .gpx in Finder to see it here.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            if !madeDefault {
              HStack {
                Spacer()
                Button("Not Now") {
                    DefaultHandler.dismissOffer()
                    showDefaultOffer = false
                }
                .buttonStyle(.glass)
                Button("Use Trace") {
                    DefaultHandler.makeDefault { ok in
                        madeDefault = ok
                        if !ok { showDefaultOffer = false }
                        if ok {
                            Task {
                                try? await Task.sleep(for: .seconds(2.5))
                                showDefaultOffer = false
                            }
                        }
                    }
                }
                .buttonStyle(.glassProminent)
              }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: 270)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Picker("Map style", selection: $flavor) {
                ForEach(MapFlavor.allCases) { f in
                    Label(f.label, systemImage: f.symbol).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .help("Map style")
        }
        ToolbarSpacer(.fixed)
        ToolbarItemGroup {
            Toggle(isOn: $playback.flyover) {
                Label("Flyover", systemImage: "video.fill")
            }
            .help("Follow the rider with a cinematic camera during playback (⇧⌘F)")
            Toggle(isOn: $playback.showMoments) {
                Label("Moments", systemImage: "sparkles")
            }
            .help("Show detected moments on the map")
            Button {
                fit()
            } label: {
                Label("Fit to Track", systemImage: "arrow.down.left.and.arrow.up.right")
            }
            .help("Show the whole track")
        }
        ToolbarSpacer(.fixed)
        ToolbarItemGroup {
            Toggle(isOn: $showStats) {
                Label("Summary", systemImage: "sidebar.left")
            }
            .help("Show ride summary")
            Toggle(isOn: $showMomentsCard) {
                Label("Moments List", systemImage: "sidebar.right")
            }
            .help("Show moments list")
        }
    }

}

// MARK: - Markers

struct MomentPin: View {
    let moment: Moment
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: moment.symbol)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(MomentsCard.tint(moment.kind).gradient, in: .circle)
                    if !moment.detail.isEmpty {
                        Text(moment.detail)
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .padding(.trailing, 4)
                    }
                }
                .padding(4)
                .background(.regularMaterial, in: .capsule)
                .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
                Triangle()
                    .fill(.white.opacity(0.9))
                    .frame(width: 10, height: 6)
                    .offset(y: -1)
            }
        }
        .buttonStyle(.plain)
        .help(moment.title)
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

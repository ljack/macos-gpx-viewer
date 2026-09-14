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
    var style: MapStyle {
        switch self {
        case .standard: .standard(elevation: .realistic, emphasis: .muted)
        case .hybrid: .hybrid(elevation: .realistic)
        case .satellite: .imagery(elevation: .realistic)
        }
    }
}

struct TrackView: View {
    let track: Track
    @State private var playback: Playback
    @State private var camera: MapCameraPosition
    @State private var flavor: MapFlavor = .standard
    @State private var heading: Double = 0
    @State private var mapHeading: Double = 0
    @State private var entryAnimationUntil: ContinuousClock.Instant = .now
    @State private var showDefaultOffer = DefaultHandler.shouldOffer
    @State private var madeDefault = false
    @State private var showStats = true
    @State private var showMomentsCard = true
    @Namespace private var glass

    private let runs: [ColourRun]

    init(track: Track) {
        self.track = track
        _playback = State(initialValue: Playback(duration: track.duration))
        _camera = State(initialValue: .rect(Self.fitRect(track.mapRect)))
        runs = track.colourRuns()
    }

    private static func fitRect(_ rect: MKMapRect) -> MKMapRect {
        rect.insetBy(dx: -rect.width * 0.18, dy: -rect.height * 0.18)
    }

    private var current: Sample { track.sample(at: playback.elapsed) }

    var body: some View {
        ZStack {
            map
            overlays
        }
        .toolbar { toolbar }
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .onAppear {
            registerCommands()
            if let mode = ProcessInfo.processInfo.environment["TRACE_APPEARANCE"] {
                NSApp.appearance = NSAppearance(named: mode == "dark" ? .darkAqua : .aqua)
            }
            if let raw = ProcessInfo.processInfo.environment["TRACE_AUTOPLAY"], let f = Double(raw) {
                playback.seek(track.duration * f)
                playback.play()
            }
        }
        .onChange(of: playback.elapsed) { _, _ in followIfNeeded() }
        .onChange(of: playback.flyover) { _, on in
            if on { followIfNeeded(animated: true) } else { fit() }
        }
        .onChange(of: playback.isPlaying) { _, playing in
            if playing { followIfNeeded(animated: true) }
        }
        .frame(minWidth: 900, minHeight: 600)
    }

    // MARK: - Map

    private var map: some View {
        Map(position: $camera, interactionModes: .all) {
            ForEach(runs) { run in
                MapPolyline(coordinates: run.coordinates)
                    .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
            }
            ForEach(runs) { run in
                MapPolyline(coordinates: run.coordinates)
                    .stroke(SpeedPalette.color(run.fraction), style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round))
            }

            ForEach(track.waypoints) { wp in
                Marker(wp.name, systemImage: "mappin", coordinate: wp.coordinate)
                    .tint(.purple)
            }

            if playback.showMoments {
                ForEach(track.moments) { moment in
                    Annotation(moment.title, coordinate: moment.coordinate, anchor: .bottom) {
                        MomentPin(moment: moment) {
                            playback.pause()
                            withAnimation(.snappy) { playback.seek(moment.t) }
                        }
                    }
                    .annotationTitles(.hidden)
                }
            }

            Annotation("Rider", coordinate: current.coordinate, anchor: .center) {
                RiderMarker(bearing: current.bearing - mapHeading, color: SpeedPalette.color(track.speedFraction(current.speed)),
                            playing: playback.isPlaying)
            }
            .annotationTitles(.hidden)
        }
        .mapStyle(flavor.style)
        .onMapCameraChange(frequency: .continuous) { context in
            mapHeading = context.camera.heading
        }
        .mapControls {
            MapCompass()
            MapScaleView()
            MapPitchToggle()
            MapZoomStepper()
        }
        .safeAreaPadding(.bottom, 128)
        .ignoresSafeArea()
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

    // MARK: - Camera

    private func fit() {
        withAnimation(.smooth(duration: 0.8)) {
            camera = .rect(Self.fitRect(track.mapRect))
        }
    }

    private func followIfNeeded(animated: Bool = false) {
        guard playback.flyover else { return }
        let s = current
        var delta = s.bearing - heading
        if delta > 180 { delta -= 360 } else if delta < -180 { delta += 360 }
        heading += delta * 0.08
        if heading < 0 { heading += 360 } else if heading >= 360 { heading -= 360 }
        let cam = MapCamera(centerCoordinate: s.coordinate, distance: 1400, heading: heading, pitch: 62)
        if animated {
            heading = s.bearing
            entryAnimationUntil = .now + .seconds(1.3)
            withAnimation(.smooth(duration: 1.2)) {
                camera = .camera(MapCamera(centerCoordinate: s.coordinate, distance: 1400, heading: heading, pitch: 62))
            }
        } else if ContinuousClock.now >= entryAnimationUntil {
            // Direct assignment: an implicit animation per tick would lag behind the rider at high rates.
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) { camera = .camera(cam) }
        }
    }

    private func registerCommands() {
        let c = PlaybackCommands.shared
        c.togglePlay = { playback.toggle() }
        c.skip = { playback.pause(); playback.skip($0) }
        c.seekFraction = { playback.pause(); playback.seek(track.duration * $0) }
        c.toggleFlyover = { playback.flyover.toggle() }
    }
}

// MARK: - Markers

private struct RiderMarker: View {
    let bearing: Double
    let color: Color
    let playing: Bool

    var body: some View {
        ZStack {
            if playing {
                Circle()
                    .fill(color.opacity(0.25))
                    .frame(width: 44, height: 44)
            }
            Circle()
                .fill(.white)
                .frame(width: 26, height: 26)
                .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
            Circle()
                .fill(color.gradient)
                .frame(width: 20, height: 20)
            Image(systemName: "location.north.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .rotationEffect(.degrees(bearing))
        }
        .animation(.linear(duration: 0.1), value: bearing)
        .accessibilityLabel("Rider position")
    }
}

private struct MomentPin: View {
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
                .glassEffect(.regular, in: .capsule)
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

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

import SwiftUI
import MapKit
import QuartzCore

/// The map plus everything that moves with playback. Backed by MKMapView directly so that per-frame
/// updates (camera, rider) bypass SwiftUI diffing entirely: the display-link tick writes straight to MapKit.
struct MapStage: NSViewRepresentable {
    let track: Track
    let playback: Playback
    let flavor: MapFlavor
    let showMoments: Bool
    let fitRequest: Int
    let onSeek: (TimeInterval) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(track: track, playback: playback, onSeek: onSeek) }

    func makeNSView(context: Context) -> MKMapView {
        let map = MKMapView()
        context.coordinator.attach(map)
        return map
    }

    func updateNSView(_ map: MKMapView, context: Context) {
        let c = context.coordinator
        c.apply(flavor: flavor)
        c.setMomentsVisible(showMoments)
        if c.lastFitRequest != fitRequest {
            c.lastFitRequest = fitRequest
            c.fit(animated: true)
        }
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, @preconcurrency MKMapViewDelegate {
        let track: Track
        let playback: Playback
        let onSeek: (TimeInterval) -> Void
        weak var map: MKMapView?

        private let rider = RiderAnnotation()
        private var riderView: RiderAnnotationView?
        private var momentAnnotations: [MomentAnnotation] = []
        private var momentsVisible = true
        private var flavor: MapFlavor?
        var lastFitRequest = 0

        private var heading: Double = 0
        private var cameraCenter: CLLocationCoordinate2D?
        private var lastTick: CFTimeInterval = CACurrentMediaTime()
        private var entryAnimationUntil: CFTimeInterval = 0
        private var wasFlyover = true
        private var wasPlaying = false
        private static let cameraLog = ProcessInfo.processInfo.environment["TRACE_CAMLOG"] != nil

        init(track: Track, playback: Playback, onSeek: @escaping (TimeInterval) -> Void) {
            self.track = track
            self.playback = playback
            self.onSeek = onSeek
            super.init()
        }

        func attach(_ map: MKMapView) {
            self.map = map
            map.delegate = self
            map.showsCompass = true
            map.showsScale = false
            map.showsPitchControl = true
            map.showsZoomControls = true
            map.isPitchEnabled = true
            map.isRotateEnabled = true
            map.pointOfInterestFilter = .includingAll
            map.additionalSafeAreaInsets = NSEdgeInsets(top: 0, left: 0, bottom: 128, right: 0)
            map.register(RiderAnnotationView.self, forAnnotationViewWithReuseIdentifier: RiderAnnotationView.identifier)
            map.register(MomentAnnotationView.self, forAnnotationViewWithReuseIdentifier: MomentAnnotationView.identifier)

            addTrack(to: map)
            momentAnnotations = track.moments.map(MomentAnnotation.init)
            map.addAnnotations(momentAnnotations)
            for wp in track.waypoints {
                let a = MKPointAnnotation()
                a.coordinate = wp.coordinate
                a.title = wp.name
                map.addAnnotation(a)
            }
            rider.coordinate = track.sample(at: playback.elapsed).coordinate
            map.addAnnotation(rider)
            fit(animated: false)

            playback.elapsedHandler = { [weak self] t in self?.tick(t) }
            observePlayback()
        }

        // MARK: Track overlays

        private func addTrack(to map: MKMapView) {
            let s = track.samples
            guard s.count > 1 else { return }
            var start = 0
            for i in 1...s.count {
                if i == s.count || s[i].segment != s[start].segment {
                    let slice = Array(s[start..<i])
                    if slice.count > 1 {
                        let coords = slice.map(\.coordinate)
                        let casing = MKPolyline(coordinates: coords, count: coords.count)
                        casing.title = "casing"
                        let line = SpeedPolyline(coordinates: coords, count: coords.count)
                        let d0 = slice.first!.distance, span = max(slice.last!.distance - d0, 1)
                        line.colors = slice.map { NSColor(SpeedPalette.color(track.speedFraction($0.speed))) }
                        line.locations = slice.map { CGFloat(($0.distance - d0) / span) }
                        map.addOverlay(casing, level: .aboveRoads)
                        map.addOverlay(line, level: .aboveRoads)
                    }
                    start = i
                }
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let line = overlay as? SpeedPolyline {
                let r = MKGradientPolylineRenderer(polyline: line)
                r.setColors(line.colors, locations: line.locations)
                r.lineWidth = 4.5
                r.lineCap = .round
                r.lineJoin = .round
                return r
            }
            if let line = overlay as? MKPolyline {
                let r = MKPolylineRenderer(polyline: line)
                r.strokeColor = NSColor.white.withAlphaComponent(0.9)
                r.lineWidth = 11
                r.lineCap = .round
                r.lineJoin = .round
                return r
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        // MARK: Annotations

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            do {
                if annotation is RiderAnnotation {
                    let v = mapView.dequeueReusableAnnotationView(withIdentifier: RiderAnnotationView.identifier, for: annotation) as! RiderAnnotationView
                    v.zPriority = .max
                    v.displayPriority = .required
                    riderView = v
                    v.setPlaying(playback.isPlaying)
                    updateRiderAppearance(track.sample(at: playback.elapsed))
                    return v
                }
                if let m = annotation as? MomentAnnotation {
                    let v = mapView.dequeueReusableAnnotationView(withIdentifier: MomentAnnotationView.identifier, for: annotation) as! MomentAnnotationView
                    v.configure(moment: m.moment) { [weak self] in self?.onSeek(m.moment.t) }
                    v.displayPriority = .defaultHigh
                    return v
                }
                if annotation is MKPointAnnotation {
                    let v = mapView.dequeueReusableAnnotationView(withIdentifier: MKMapViewDefaultAnnotationViewReuseIdentifier, for: annotation)
                    (v as? MKMarkerAnnotationView)?.markerTintColor = .systemPurple
                    return v
                }
                return nil
            }
        }

        func setMomentsVisible(_ visible: Bool) {
            guard visible != momentsVisible, let map else { return }
            momentsVisible = visible
            if visible { map.addAnnotations(momentAnnotations) } else { map.removeAnnotations(momentAnnotations) }
        }

        func apply(flavor: MapFlavor) {
            guard flavor != self.flavor, let map else { return }
            self.flavor = flavor
            switch flavor {
            case .standard:
                let c = MKStandardMapConfiguration(elevationStyle: .realistic, emphasisStyle: .muted)
                map.preferredConfiguration = c
            case .hybrid:
                map.preferredConfiguration = MKHybridMapConfiguration(elevationStyle: .realistic)
            case .satellite:
                map.preferredConfiguration = MKImageryMapConfiguration(elevationStyle: .realistic)
            }
        }

        // MARK: Camera

        func fit(animated: Bool) {
            guard let map else { return }
            let rect = track.mapRect.insetBy(dx: -track.mapRect.width * 0.12, dy: -track.mapRect.height * 0.12)
            let padding = NSEdgeInsets(top: 80, left: 330, bottom: 40, right: 300)
            map.setVisibleMapRect(rect, edgePadding: padding, animated: animated)
            cameraCenter = nil
        }

        private func observePlayback() {
            withObservationTracking {
                _ = playback.flyover
                _ = playback.isPlaying
            } onChange: { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let flyover = playback.flyover, playing = playback.isPlaying
                    if flyover != wasFlyover {
                        wasFlyover = flyover
                        if flyover { enter() } else { fit(animated: true) }
                    }
                    if playing != wasPlaying {
                        wasPlaying = playing
                        riderView?.setPlaying(playing)
                        if playing, flyover { enter() }
                    }
                    observePlayback()
                }
            }
        }

        /// Swoop from wherever the camera is to the rider, then hand over to per-frame following.
        private func enter() {
            guard let map else { return }
            let t = playback.elapsed
            let target = track.smooth.position(at: t)
            heading = track.smooth.bearing(at: t) ?? heading
            cameraCenter = target
            entryAnimationUntil = CACurrentMediaTime() + 1.3
            let cam = MKMapCamera(lookingAtCenter: target, fromDistance: 1400, pitch: 62, heading: heading)
            map.setCamera(cam, animated: true)
        }

        private func tick(_ t: TimeInterval) {
            let sample = track.sample(at: t)
            rider.coordinate = sample.coordinate
            updateRiderAppearance(sample)
            follow(t)
        }

        private func follow(_ t: TimeInterval) {
            guard playback.flyover, let map else { return }
            let now = CACurrentMediaTime()
            let dt = min(max(now - lastTick, 0), 0.25)
            lastTick = now
            guard now >= entryAnimationUntil else { return }

            let target = track.smooth.position(at: t)
            let targetBearing = track.smooth.bearing(at: t) ?? heading

            let kHeading = 1 - exp(-dt / 0.7)
            var delta = targetBearing - heading
            if delta > 180 { delta -= 360 } else if delta < -180 { delta += 360 }
            heading += delta * kHeading
            if heading < 0 { heading += 360 } else if heading >= 360 { heading -= 360 }

            let kCenter = 1 - exp(-dt / 0.12)
            let previous = cameraCenter ?? target
            let center = CLLocationCoordinate2D(latitude: previous.latitude + (target.latitude - previous.latitude) * kCenter,
                                                longitude: previous.longitude + (target.longitude - previous.longitude) * kCenter)
            cameraCenter = center

            if Self.cameraLog {
                FileHandle.standardError.write("SET \(ProcessInfo.processInfo.systemUptime) \(t) \(center.latitude) \(center.longitude) \(heading)\n".data(using: .utf8)!)
            }
            map.camera = MKMapCamera(lookingAtCenter: center, fromDistance: 1400, pitch: 62, heading: heading)
        }

        private func updateRiderAppearance(_ sample: Sample) {
            guard let riderView, let map else { return }
            let bearing = (track.smooth.bearing(at: sample.t) ?? sample.bearing) - map.camera.heading
            riderView.update(bearing: bearing, color: NSColor(SpeedPalette.color(track.speedFraction(sample.speed))))
        }

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            do {
                if Self.cameraLog {
                    let c = mapView.camera
                    FileHandle.standardError.write("CAM \(ProcessInfo.processInfo.systemUptime) \(playback.elapsed) \(c.centerCoordinate.latitude) \(c.centerCoordinate.longitude) \(c.heading)\n".data(using: .utf8)!)
                }
                if !playback.isPlaying { updateRiderAppearance(track.sample(at: playback.elapsed)) }
            }
        }
    }
}

// MARK: - Overlays and annotations

nonisolated final class SpeedPolyline: MKPolyline {
    var colors: [NSColor] = []
    var locations: [CGFloat] = []
}

nonisolated final class RiderAnnotation: MKPointAnnotation {}

final class MomentAnnotation: NSObject, MKAnnotation {
    let moment: Moment
    var coordinate: CLLocationCoordinate2D { moment.coordinate }
    init(moment: Moment) { self.moment = moment }
}

/// Rider marker: a pulse ring on a layer, plus a tiny SwiftUI glyph for the coloured dot and heading arrow.
/// Updating the glyph's root view per frame costs a fraction of a millisecond.
final class RiderAnnotationView: MKAnnotationView {
    static let identifier = "rider"
    private let pulse = CAShapeLayer()
    private var host: NSHostingView<RiderGlyph>?
    private var pulseColor = NSColor.systemBlue

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        wantsLayer = true
        layer?.masksToBounds = false
        pulse.path = CGPath(ellipseIn: CGRect(x: 0, y: 0, width: 44, height: 44), transform: nil)
        pulse.fillColor = pulseColor.withAlphaComponent(0.25).cgColor
        pulse.opacity = 0
        layer?.addSublayer(pulse)
        let h = NSHostingView(rootView: RiderGlyph(bearing: 0, color: .blue))
        h.frame = bounds
        h.autoresizingMask = [.width, .height]
        addSubview(h)
        host = h
    }

    required init?(coder: NSCoder) { nil }

    func update(bearing: Double, color: NSColor) {
        host?.rootView = RiderGlyph(bearing: bearing, color: Color(nsColor: color))
        if color != pulseColor {
            pulseColor = color
            CATransaction.begin(); CATransaction.setDisableActions(true)
            pulse.fillColor = color.withAlphaComponent(0.25).cgColor
            CATransaction.commit()
        }
    }

    func setPlaying(_ playing: Bool) {
        pulse.removeAllAnimations()
        if playing {
            let a = CABasicAnimation(keyPath: "transform.scale")
            a.fromValue = 0.6; a.toValue = 1.15
            let o = CABasicAnimation(keyPath: "opacity")
            o.fromValue = 0.9; o.toValue = 0
            let g = CAAnimationGroup()
            g.animations = [a, o]; g.duration = 1.6; g.repeatCount = .infinity
            g.timingFunction = CAMediaTimingFunction(name: .easeOut)
            pulse.add(g, forKey: "pulse")
        } else {
            pulse.opacity = 0
        }
    }
}

struct RiderGlyph: View {
    var bearing: Double
    var color: Color

    var body: some View {
        ZStack {
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
        .frame(width: 44, height: 44)
    }
}

final class MomentAnnotationView: MKAnnotationView {
    static let identifier = "moment"
    private var host: NSHostingView<MomentPin>?

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { nil }

    func configure(moment: Moment, action: @escaping () -> Void) {
        host?.removeFromSuperview()
        let h = NSHostingView(rootView: MomentPin(moment: moment, action: action))
        h.translatesAutoresizingMaskIntoConstraints = true
        let size = h.fittingSize
        h.frame = CGRect(origin: .zero, size: size)
        frame = CGRect(origin: .zero, size: size)
        centerOffset = CGPoint(x: 0, y: -size.height / 2)
        addSubview(h)
        host = h
    }
}

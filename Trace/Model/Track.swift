import Foundation
import CoreLocation
import MapKit

/// One resampled point along a track with everything the UI needs precomputed.
nonisolated struct Sample: Sendable {
    var latitude: Double
    var longitude: Double
    /// Seconds since track start (synthesised from distance when the file has no timestamps).
    var t: TimeInterval
    /// Cumulative distance in metres.
    var distance: Double
    /// Smoothed speed in m/s.
    var speed: Double
    /// Course over ground in degrees, 0 = north.
    var bearing: Double
    var elevation: Double?
    var segment: Int

    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}

nonisolated struct Waypoint: Sendable, Identifiable {
    let id = UUID()
    var name: String
    var latitude: Double
    var longitude: Double
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}

nonisolated struct Moment: Sendable, Identifiable {
    enum Kind: Sendable { case start, finish, stop, fastestKilometre, topSpeed, turnaround }
    let id = UUID()
    var kind: Kind
    var title: String
    var detail: String
    var t: TimeInterval
    var latitude: Double
    var longitude: Double
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }

    var symbol: String {
        switch kind {
        case .start: "figure.outdoor.cycle"
        case .finish: "flag.pattern.checkered"
        case .stop: "pause.fill"
        case .fastestKilometre: "hare.fill"
        case .topSpeed: "bolt.fill"
        case .turnaround: "arrow.uturn.backward"
        }
    }
}

nonisolated struct TrackStats: Sendable {
    var distance: Double = 0          // m
    var duration: TimeInterval = 0    // s
    var movingTime: TimeInterval = 0  // s
    var averageMovingSpeed: Double = 0 // m/s
    var maxSpeed: Double = 0          // m/s
    var elevationGain: Double? = nil  // m
    var speedFloor: Double = 0        // 5th percentile, used for colouring
    var speedCeiling: Double = 0      // 95th percentile
}

nonisolated struct Track: Sendable {
    var name: String
    var startDate: Date?
    var hasTime: Bool
    var hasElevation: Bool
    var samples: [Sample]
    var waypoints: [Waypoint]
    var stats: TrackStats
    var moments: [Moment]
    var mapRect: MKMapRect
    var smooth: SmoothPath

    var duration: TimeInterval { samples.last?.t ?? 0 }
    var endDate: Date? { startDate.map { $0.addingTimeInterval(duration) } }

    // MARK: - Interpolation

    /// Index of the last sample whose `t` is <= the given time.
    func index(at t: TimeInterval) -> Int {
        var lo = 0, hi = samples.count - 1
        if hi < 0 { return 0 }
        if t <= samples[0].t { return 0 }
        if t >= samples[hi].t { return hi }
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if samples[mid].t <= t { lo = mid } else { hi = mid }
        }
        return lo
    }

    /// Linear interpolation between neighbouring samples.
    func sample(at t: TimeInterval) -> Sample {
        guard !samples.isEmpty else {
            return Sample(latitude: 0, longitude: 0, t: 0, distance: 0, speed: 0, bearing: 0, elevation: nil, segment: 0)
        }
        let i = index(at: t)
        let a = samples[i]
        guard i + 1 < samples.count else { return a }
        let b = samples[i + 1]
        if b.segment != a.segment { return t - a.t < b.t - t ? a : b }
        let span = b.t - a.t
        let f = span > 0 ? min(max((t - a.t) / span, 0), 1) : 0
        func lerp(_ x: Double, _ y: Double) -> Double { x + (y - x) * f }
        var delta = b.bearing - a.bearing
        if delta > 180 { delta -= 360 } else if delta < -180 { delta += 360 }
        var bearing = a.bearing + delta * f
        if bearing < 0 { bearing += 360 } else if bearing >= 360 { bearing -= 360 }
        return Sample(
            latitude: lerp(a.latitude, b.latitude),
            longitude: lerp(a.longitude, b.longitude),
            t: t,
            distance: lerp(a.distance, b.distance),
            speed: lerp(a.speed, b.speed),
            bearing: bearing,
            elevation: a.elevation.flatMap { ea in b.elevation.map { lerp(ea, $0) } },
            segment: a.segment)
    }

    /// Consecutive runs of samples in the same segment, split into speed bands for colouring.
    func colourRuns(bands: Int = 14) -> [ColourRun] {
        guard samples.count > 1 else { return [] }
        var runs: [ColourRun] = []
        var current: [CLLocationCoordinate2D] = [samples[0].coordinate]
        var currentBand = band(for: samples[1].speed, bands: bands)
        var currentSegment = samples[0].segment
        for i in 1..<samples.count {
            let s = samples[i]
            let b = band(for: s.speed, bands: bands)
            if s.segment != currentSegment {
                if current.count > 1 { runs.append(ColourRun(coordinates: current, fraction: fraction(ofBand: currentBand, bands: bands))) }
                current = [s.coordinate]
                currentBand = b
                currentSegment = s.segment
                continue
            }
            if b != currentBand {
                current.append(s.coordinate)
                runs.append(ColourRun(coordinates: current, fraction: fraction(ofBand: currentBand, bands: bands)))
                current = [s.coordinate]
                currentBand = b
            } else {
                current.append(s.coordinate)
            }
        }
        if current.count > 1 { runs.append(ColourRun(coordinates: current, fraction: fraction(ofBand: currentBand, bands: bands))) }
        return runs
    }

    func speedFraction(_ speed: Double) -> Double {
        let range = stats.speedCeiling - stats.speedFloor
        guard range > 0 else { return 0.5 }
        return min(max((speed - stats.speedFloor) / range, 0), 1)
    }

    private func band(for speed: Double, bands: Int) -> Int {
        min(Int(speedFraction(speed) * Double(bands)), bands - 1)
    }

    private func fraction(ofBand band: Int, bands: Int) -> Double {
        (Double(band) + 0.5) / Double(bands)
    }
}

nonisolated struct ColourRun: Identifiable, Sendable {
    let id = UUID()
    var coordinates: [CLLocationCoordinate2D]
    /// 0 = slowest, 1 = fastest.
    var fraction: Double
}

/// A denoised version of the track sampled on a uniform time grid. Used for the flyover camera
/// and the rider's heading, so GPS jitter and polyline corners don't shake the view.
nonisolated struct SmoothPath: Sendable {
    var step: TimeInterval
    var latitudes: [Double]
    var longitudes: [Double]

    var duration: TimeInterval { Double(max(latitudes.count - 1, 0)) * step }

    func position(at t: TimeInterval) -> CLLocationCoordinate2D {
        guard latitudes.count > 1 else {
            return CLLocationCoordinate2D(latitude: latitudes.first ?? 0, longitude: longitudes.first ?? 0)
        }
        let x = min(max(t / step, 0), Double(latitudes.count - 1))
        let i = min(Int(x), latitudes.count - 2)
        let f = x - Double(i)
        return CLLocationCoordinate2D(latitude: latitudes[i] + (latitudes[i + 1] - latitudes[i]) * f,
                                      longitude: longitudes[i] + (longitudes[i + 1] - longitudes[i]) * f)
    }

    /// Direction of travel across a window centred on `t`, in degrees from north.
    func bearing(at t: TimeInterval, span: TimeInterval = 6) -> Double? {
        let a = position(at: t - span), b = position(at: t + span)
        let dLat = b.latitude - a.latitude
        let dLon = (b.longitude - a.longitude) * cos((a.latitude + b.latitude) / 2 * .pi / 180)
        guard abs(dLat) + abs(dLon) > 1e-7 else { return nil }
        var deg = atan2(dLon, dLat) * 180 / .pi
        if deg < 0 { deg += 360 }
        return deg
    }

    static func build(from samples: [Sample], duration: TimeInterval, window: TimeInterval = 8) -> SmoothPath {
        guard samples.count > 1, duration > 0 else {
            return SmoothPath(step: 1, latitudes: samples.map(\.latitude), longitudes: samples.map(\.longitude))
        }
        // Keep the grid bounded for very long recordings.
        let step = max(1, (duration / 20_000).rounded(.up))
        let count = Int(duration / step) + 1
        // Raw positions on the grid (linear interpolation along the polyline).
        var rawLat = [Double](repeating: 0, count: count)
        var rawLon = [Double](repeating: 0, count: count)
        var j = 0
        for k in 0..<count {
            let t = Double(k) * step
            while j + 1 < samples.count - 1, samples[j + 1].t <= t { j += 1 }
            let a = samples[j], b = samples[min(j + 1, samples.count - 1)]
            let span = b.t - a.t
            let f = span > 0 ? min(max((t - a.t) / span, 0), 1) : 0
            rawLat[k] = a.latitude + (b.latitude - a.latitude) * f
            rawLon[k] = a.longitude + (b.longitude - a.longitude) * f
        }
        // Triangular-weighted moving average over ±window (two box passes = triangle).
        let radius = max(1, Int(window / step))
        func box(_ v: [Double]) -> [Double] {
            var out = v
            var sum = 0.0
            var lo = 0, hi = -1
            for k in v.indices {
                let targetHi = min(k + radius, v.count - 1)
                while hi < targetHi { hi += 1; sum += v[hi] }
                let targetLo = max(k - radius, 0)
                while lo < targetLo { sum -= v[lo]; lo += 1 }
                out[k] = sum / Double(hi - lo + 1)
            }
            return out
        }
        return SmoothPath(step: step, latitudes: box(box(rawLat)), longitudes: box(box(rawLon)))
    }
}

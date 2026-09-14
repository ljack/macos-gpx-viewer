import Foundation
import CoreLocation
import MapKit

/// Turns raw GPX points into an analysed `Track`.
nonisolated enum TrackBuilder {
    /// Below this speed the rider is considered stationary.
    static let stationarySpeed = 0.6 // m/s
    /// A stationary run shorter than this is noise, not a stop.
    static let minimumStop: TimeInterval = 90

    static func build(from file: GPXFile, fallbackName: String) -> Track {
        var raw: [(GPXPoint, Int)] = []
        for (i, seg) in file.segments.enumerated() {
            for p in seg { raw.append((p, i)) }
        }

        let timed = raw.filter { $0.0.time != nil }.count
        let hasTime = timed >= 2 && timed >= raw.count / 2
        let hasElevation = raw.contains { $0.0.elevation != nil }
        let start = hasTime ? raw.compactMap { $0.0.time }.min() : nil

        // Cumulative distance and raw per-segment speed.
        var samples: [Sample] = []
        samples.reserveCapacity(raw.count)
        var distance = 0.0
        var previous: (GPXPoint, Int)?
        var rawSpeeds: [Double] = []
        var lastT = 0.0
        for (p, seg) in raw {
            var t: TimeInterval
            var speed = 0.0
            var bearing = 0.0
            if let prev = previous {
                let d = haversine(prev.0, p)
                if prev.1 == seg { distance += d }
                if hasTime, let pt = p.time, let start {
                    t = max(pt.timeIntervalSince(start), lastT)
                } else {
                    t = lastT + d / 5.0 // synthesise 5 m/s pacing
                }
                let dt = t - lastT
                speed = dt > 0 ? d / dt : 0
                bearing = Self.bearing(prev.0, p)
            } else {
                t = 0
            }
            rawSpeeds.append(speed)
            samples.append(Sample(latitude: p.latitude, longitude: p.longitude, t: t, distance: distance,
                                  speed: speed, bearing: bearing, elevation: p.elevation, segment: seg))
            lastT = t
            previous = (p, seg)
        }
        if samples.count > 1 {
            samples[0].speed = rawSpeeds[1]
            samples[0].bearing = samples[1].bearing
            rawSpeeds[0] = rawSpeeds[1]
        }

        // Smooth speed with a small time-aware window.
        let smoothed = smooth(rawSpeeds, times: samples.map(\.t), window: 12)
        for i in samples.indices { samples[i].speed = smoothed[i] }

        // Stats.
        var stats = TrackStats()
        stats.distance = distance
        stats.duration = samples.last?.t ?? 0
        var moving = 0.0
        for i in 1..<max(samples.count, 1) {
            let dt = samples[i].t - samples[i - 1].t
            if rawSpeeds[i] >= stationarySpeed { moving += dt }
        }
        stats.movingTime = moving
        stats.averageMovingSpeed = moving > 0 ? distance / moving : 0
        stats.maxSpeed = smoothed.max() ?? 0
        let sorted = smoothed.filter { $0 > 0 }.sorted()
        if !sorted.isEmpty {
            stats.speedFloor = sorted[Int(Double(sorted.count - 1) * 0.05)]
            stats.speedCeiling = sorted[Int(Double(sorted.count - 1) * 0.95)]
        }
        if hasElevation {
            var gain = 0.0
            var last: Double?
            for s in samples {
                if let e = s.elevation {
                    if let l = last, e > l { gain += e - l }
                    last = e
                }
            }
            stats.elevationGain = gain
        }

        let waypoints = file.waypoints.map { Waypoint(name: $0.name, latitude: $0.point.latitude, longitude: $0.point.longitude) }
        var track = Track(name: file.name ?? fallbackName, startDate: start, hasTime: hasTime, hasElevation: hasElevation,
                          samples: samples, waypoints: waypoints, stats: stats, moments: [], mapRect: mapRect(for: samples))
        track.moments = moments(for: track, rawSpeeds: rawSpeeds)
        return track
    }

    // MARK: - Moments

    private static func moments(for track: Track, rawSpeeds: [Double]) -> [Moment] {
        let s = track.samples
        guard s.count > 1 else { return [] }
        var result: [Moment] = []

        result.append(Moment(kind: .start, title: "Start", detail: "", t: s[0].t, latitude: s[0].latitude, longitude: s[0].longitude))

        if track.hasTime {
            // Stops: runs of stationary raw speed.
            var runStart: Int?
            for i in 1..<s.count {
                let stationary = rawSpeeds[i] < stationarySpeed
                if stationary, runStart == nil { runStart = i - 1 }
                if (!stationary || i == s.count - 1), let r = runStart {
                    let end = stationary ? i : i - 1
                    let duration = s[end].t - s[r].t
                    if duration >= minimumStop, r > 0, end < s.count - 1 {
                        result.append(Moment(kind: .stop, title: "Stopped",
                                             detail: Format.duration(duration), t: s[r].t,
                                             latitude: s[r].latitude, longitude: s[r].longitude))
                    }
                    runStart = nil
                }
            }

            // Top speed.
            if let maxIndex = s.indices.max(by: { s[$0].speed < s[$1].speed }), s[maxIndex].speed > 0 {
                let m = s[maxIndex]
                result.append(Moment(kind: .topSpeed, title: "Top speed", detail: Format.speed(m.speed),
                                     t: m.t, latitude: m.latitude, longitude: m.longitude))
            }

            // Fastest kilometre (two-pointer over cumulative distance).
            if track.stats.distance >= 1000 {
                var j = 0
                var best: (start: Int, duration: TimeInterval)?
                for i in s.indices {
                    while j < s.count, s[j].distance - s[i].distance < 1000 { j += 1 }
                    guard j < s.count else { break }
                    let d = s[j].t - s[i].t
                    if d > 0, best == nil || d < best!.duration { best = (i, d) }
                }
                if let best {
                    let m = s[best.start]
                    result.append(Moment(kind: .fastestKilometre, title: "Fastest kilometre",
                                         detail: Format.speed(1000 / best.duration), t: m.t,
                                         latitude: m.latitude, longitude: m.longitude))
                }
            }
        }

        // Turnaround: farthest point from start, if the ride actually comes back.
        if track.stats.distance >= 1000 {
            let origin = s[0]
            var farIndex = 0
            var farDistance = 0.0
            for i in s.indices {
                let d = haversine(GPXPoint(latitude: origin.latitude, longitude: origin.longitude),
                                  GPXPoint(latitude: s[i].latitude, longitude: s[i].longitude))
                if d > farDistance { farDistance = d; farIndex = i }
            }
            let endDistance = haversine(GPXPoint(latitude: origin.latitude, longitude: origin.longitude),
                                        GPXPoint(latitude: s.last!.latitude, longitude: s.last!.longitude))
            if farDistance > 500, endDistance < farDistance * 0.5 {
                let m = s[farIndex]
                result.append(Moment(kind: .turnaround, title: "Farthest out",
                                     detail: Format.distance(farDistance) + " from start", t: m.t,
                                     latitude: m.latitude, longitude: m.longitude))
            }
        }

        let last = s[s.count - 1]
        result.append(Moment(kind: .finish, title: "Finish", detail: "", t: last.t, latitude: last.latitude, longitude: last.longitude))
        return result.sorted { $0.t < $1.t }
    }

    // MARK: - Geometry

    private static func smooth(_ values: [Double], times: [Double], window: TimeInterval) -> [Double] {
        guard values.count > 2 else { return values }
        var out = values
        var lo = 0, hi = 0
        var sum = 0.0, count = 0
        for i in values.indices {
            while hi < values.count, times[hi] <= times[i] + window { sum += values[hi]; count += 1; hi += 1 }
            while lo < hi, times[lo] < times[i] - window { sum -= values[lo]; count -= 1; lo += 1 }
            out[i] = count > 0 ? sum / Double(count) : values[i]
        }
        return out
    }

    private static func mapRect(for samples: [Sample]) -> MKMapRect {
        var rect = MKMapRect.null
        for s in samples {
            let p = MKMapPoint(s.coordinate)
            rect = rect.union(MKMapRect(x: p.x, y: p.y, width: 0, height: 0))
        }
        return rect
    }

    static func haversine(_ a: GPXPoint, _ b: GPXPoint) -> Double {
        let r = 6_371_000.0
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let la1 = a.latitude * .pi / 180, la2 = b.latitude * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(la1) * cos(la2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * asin(min(1, sqrt(h)))
    }

    static func bearing(_ a: GPXPoint, _ b: GPXPoint) -> Double {
        let la1 = a.latitude * .pi / 180, la2 = b.latitude * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dLon) * cos(la2)
        let x = cos(la1) * sin(la2) - sin(la1) * cos(la2) * cos(dLon)
        var deg = atan2(y, x) * 180 / .pi
        if deg < 0 { deg += 360 }
        return deg
    }
}

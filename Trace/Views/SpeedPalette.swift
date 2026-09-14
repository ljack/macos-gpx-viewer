import SwiftUI

/// Slow → fast colour ramp shared by the map, the chart and the legend.
enum SpeedPalette {
    private static let stops: [(Double, (Double, Double, Double))] = [
        (0.00, (0.20, 0.55, 0.95)),   // blue
        (0.35, (0.20, 0.80, 0.60)),   // teal-green
        (0.65, (0.98, 0.80, 0.20)),   // amber
        (0.85, (0.98, 0.50, 0.15)),   // orange
        (1.00, (0.95, 0.20, 0.25)),   // red
    ]

    static func color(_ fraction: Double) -> Color {
        let f = min(max(fraction, 0), 1)
        var lower = stops[0], upper = stops[stops.count - 1]
        for i in 0..<(stops.count - 1) where f >= stops[i].0 && f <= stops[i + 1].0 {
            lower = stops[i]; upper = stops[i + 1]; break
        }
        let span = upper.0 - lower.0
        let k = span > 0 ? (f - lower.0) / span : 0
        func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * k }
        return Color(red: mix(lower.1.0, upper.1.0), green: mix(lower.1.1, upper.1.1), blue: mix(lower.1.2, upper.1.2))
    }

    static var gradient: LinearGradient {
        LinearGradient(colors: stride(from: 0.0, through: 1.0, by: 0.1).map(color), startPoint: .leading, endPoint: .trailing)
    }
}

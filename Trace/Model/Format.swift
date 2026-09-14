import Foundation

nonisolated enum Format {
    static var usesMetric: Bool { Locale.current.measurementSystem == .metric }

    static func distance(_ metres: Double) -> String {
        Measurement(value: metres, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road,
                                    numberFormatStyle: .number.precision(.fractionLength(metres < 10_000 ? 1 : 0))))
    }

    static func speed(_ metresPerSecond: Double) -> String {
        let value: Measurement<UnitSpeed> = usesMetric
            ? Measurement(value: metresPerSecond * 3.6, unit: .kilometersPerHour)
            : Measurement(value: metresPerSecond * 2.23694, unit: .milesPerHour)
        return value.formatted(.measurement(width: .abbreviated, usage: .asProvided,
                                            numberFormatStyle: .number.precision(.fractionLength(0))))
    }

    static func speedNumber(_ metresPerSecond: Double) -> String {
        let v = usesMetric ? metresPerSecond * 3.6 : metresPerSecond * 2.23694
        return v.formatted(.number.precision(.fractionLength(0)))
    }

    static var speedUnit: String { usesMetric ? "km/h" : "mph" }

    static func elevation(_ metres: Double) -> String {
        Measurement(value: metres, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided,
                                    numberFormatStyle: .number.precision(.fractionLength(0))))
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let allowed: Set<Duration.UnitsFormatStyle.Unit> = seconds >= 3600 ? [.hours, .minutes] : [.minutes, .seconds]
        return Duration.seconds(seconds).formatted(.units(allowed: allowed, width: .narrow))
    }

    static func clock(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds).formatted(.time(pattern: seconds >= 3600 ? .hourMinuteSecond : .minuteSecond))
    }

    static func timeOfDay(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    static func dateLine(start: Date?, end: Date?) -> String? {
        guard let start else { return nil }
        let day = start.formatted(.dateTime.weekday(.wide).day().month(.wide).year())
        guard let end else { return day }
        return "\(day) · \(timeOfDay(start)) – \(timeOfDay(end))"
    }
}

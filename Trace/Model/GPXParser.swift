import Foundation

nonisolated struct GPXPoint {
    var latitude: Double
    var longitude: Double
    var elevation: Double?
    var time: Date?
}

nonisolated struct GPXFile {
    var name: String?
    var segments: [[GPXPoint]] = []
    var waypoints: [(name: String, point: GPXPoint)] = []
}

nonisolated enum GPXError: LocalizedError {
    case malformed(String)
    case empty

    var errorDescription: String? {
        switch self {
        case .malformed(let why): "The file isn’t valid GPX. \(why)"
        case .empty: "This GPX file contains no track points."
        }
    }
}

/// Streaming XML parser for GPX 1.0/1.1. Tracks and routes both become segments.
nonisolated final class GPXParser: NSObject, XMLParserDelegate {
    private var file = GPXFile()
    private var currentSegment: [GPXPoint]?
    private var currentPoint: GPXPoint?
    private var currentPointIsWaypoint = false
    private var text = ""
    private var elementStack: [String] = []
    private var metadataName: String?
    private var trackName: String?
    private var waypointName: String?
    private var error: String?

    nonisolated(unsafe) private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated(unsafe) private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parse(_ data: Data) throws -> GPXFile {
        let p = GPXParser()
        let xml = XMLParser(data: data)
        xml.delegate = p
        xml.shouldProcessNamespaces = true
        guard xml.parse() else {
            throw GPXError.malformed(xml.parserError?.localizedDescription ?? p.error ?? "Unknown error")
        }
        if let error = p.error { throw GPXError.malformed(error) }
        p.file.segments = p.file.segments.filter { !$0.isEmpty }
        guard !p.file.segments.isEmpty else { throw GPXError.empty }
        p.file.name = p.metadataName ?? p.trackName
        return p.file
    }

    private static func date(from raw: String) -> Date? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return isoFractional.date(from: s) ?? iso.date(from: s)
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        elementStack.append(name)
        text = ""
        switch name {
        case "trkseg":
            currentSegment = []
        case "rte":
            currentSegment = []
        case "trkpt", "rtept", "wpt":
            guard let lat = attributes["lat"].flatMap(Double.init),
                  let lon = attributes["lon"].flatMap(Double.init) else {
                error = "A point is missing its coordinates."
                parser.abortParsing()
                return
            }
            currentPoint = GPXPoint(latitude: lat, longitude: lon)
            currentPointIsWaypoint = name == "wpt"
            waypointName = nil
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        defer { _ = elementStack.popLast() }
        let parent = elementStack.dropLast().last
        switch name {
        case "ele":
            currentPoint?.elevation = Double(text.trimmingCharacters(in: .whitespacesAndNewlines))
        case "time":
            if currentPoint != nil { currentPoint?.time = Self.date(from: text) }
        case "name":
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            switch parent {
            case "metadata": metadataName = value
            case "trk", "rte": if trackName == nil { trackName = value }
            case "wpt": waypointName = value
            default: break
            }
        case "trkpt", "rtept":
            if let p = currentPoint { currentSegment?.append(p) }
            currentPoint = nil
        case "wpt":
            if let p = currentPoint { file.waypoints.append((waypointName ?? "Waypoint", p)) }
            currentPoint = nil
        case "trkseg", "rte":
            if let seg = currentSegment { file.segments.append(seg) }
            currentSegment = nil
        default:
            break
        }
    }
}

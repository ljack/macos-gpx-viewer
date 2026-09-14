import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    nonisolated static let gpx = UTType(importedAs: "com.topografix.gpx")
}

struct GPXDocument: FileDocument {
    nonisolated static let readableContentTypes: [UTType] = [.gpx, .xml]

    let track: Track

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let file = try GPXParser.parse(data)
        let fallback = configuration.file.filename.map { ($0 as NSString).deletingPathExtension } ?? "Track"
        track = TrackBuilder.build(from: file, fallbackName: fallback)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        throw CocoaError(.fileWriteNoPermission)
    }
}

import AppKit
import UniformTypeIdentifiers

enum DefaultHandler {
    static let promptedKey = "defaultHandlerPrompted"

    static var isDefault: Bool {
        guard let url = NSWorkspace.shared.urlForApplication(toOpen: .gpx) else { return false }
        return url.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL
    }

    /// Asks macOS to make Trace the default app for GPX files. The system shows its own confirmation.
    static func makeDefault(completion: (@MainActor (Bool) -> Void)? = nil) {
        UserDefaults.standard.set(true, forKey: promptedKey)
        NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpen: .gpx) { error in
            Task { @MainActor in
                completion?(error == nil)
            }
        }
    }

    static var shouldOffer: Bool {
        !UserDefaults.standard.bool(forKey: promptedKey) && !isDefault
    }

    static func dismissOffer() {
        UserDefaults.standard.set(true, forKey: promptedKey)
    }
}

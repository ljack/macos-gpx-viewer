import SwiftUI

@main
struct TraceApp: App {
    var body: some Scene {
        DocumentGroup(viewing: GPXDocument.self) { file in
            TrackView(track: file.document.track)
        }
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1280, height: 860)
        .commands {
            CommandGroup(after: .appSettings) {
                Button("Make Trace the Default GPX App…") {
                    DefaultHandler.makeDefault()
                }
            }
            CommandMenu("Playback") {
                Button("Play / Pause") { PlaybackCommands.shared.togglePlay?() }
                    .keyboardShortcut(.space, modifiers: [])
                Divider()
                Button("Skip Back 30 s") { PlaybackCommands.shared.skip?(-30) }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                Button("Skip Forward 30 s") { PlaybackCommands.shared.skip?(30) }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                Button("Skip Back 5 min") { PlaybackCommands.shared.skip?(-300) }
                    .keyboardShortcut(.leftArrow, modifiers: [.shift])
                Button("Skip Forward 5 min") { PlaybackCommands.shared.skip?(300) }
                    .keyboardShortcut(.rightArrow, modifiers: [.shift])
                Divider()
                Button("Go to Start") { PlaybackCommands.shared.seekFraction?(0) }
                    .keyboardShortcut(.home, modifiers: [])
                Button("Go to End") { PlaybackCommands.shared.seekFraction?(1) }
                    .keyboardShortcut(.end, modifiers: [])
                Divider()
                Button("Toggle Flyover") { PlaybackCommands.shared.toggleFlyover?() }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
            }
        }
    }
}

/// Menu commands need to reach whichever document window is key; the focused TrackView registers here.
@MainActor
final class PlaybackCommands {
    static let shared = PlaybackCommands()
    var togglePlay: (() -> Void)?
    var skip: ((TimeInterval) -> Void)?
    var seekFraction: ((Double) -> Void)?
    var toggleFlyover: (() -> Void)?
}

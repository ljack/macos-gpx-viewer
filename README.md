# Trace

[![Latest release](https://img.shields.io/github/v/release/ljack/macos-gpx-viewer?label=release)](https://github.com/ljack/macos-gpx-viewer/releases/latest)

A native macOS viewer for GPX tracks, built with SwiftUI, MapKit and Swift Charts for macOS 26.

Open a `.gpx` and Trace shows the ride on a full-bleed map, colours the track by speed, detects the moments that matter (stops, fastest kilometre, top speed, farthest point) and lets you replay the ride with a cinematic flyover camera that follows the rider.

## Install

Requires macOS 26 (Tahoe) on Apple silicon or Intel. The app is signed with a Developer ID and notarized.

**Homebrew**

```sh
brew install --cask ljack/tap/trace
```

Update later with `brew upgrade --cask trace`, remove with `brew uninstall --cask trace` (add `--zap` to also delete preferences).

**Download**

Grab `Trace-<version>.zip` from the [latest release](https://github.com/ljack/macos-gpx-viewer/releases/latest), unzip, and drag `Trace.app` to `/Applications`.

**Build from source**

Requires Xcode 26 and [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
make run        # Debug build, opens the sample track
make install    # Release build → /Applications/Trace.app (needs a Developer ID certificate, or edit project.yml to sign ad hoc)
```

Or `xcodegen generate` and open `Trace.xcodeproj` in Xcode.

## Releasing

`make publish` runs `Scripts/release.sh --publish`: Release build, Developer ID signature check, notarization via `notarytool` (keychain profile `md-reader-notary`, override with `NOTARY_PROFILE`), stapling, GitHub release with the zip, cask bump in `Casks/trace.rb`, and a mirror commit to `ljack/homebrew-tap`. Bump `CFBundleShortVersionString` in `project.yml` first.

## Using it

- **Play / Space** replays the ride. Choose 10×–120× from the rate menu. ← → skip 30 s, ⇧← ⇧→ skip 5 min, Home/End jump to start/finish.
- **Flyover** (⇧⌘F) follows the rider with a tilted camera turned in the direction of travel. Turn it off to keep the map still while replaying.
- **Scrub** by dragging across the speed chart. The readout shows time of day, elapsed time, distance and speed at the playhead.
- **Moments** are detected automatically. Click one in the list or on the map to jump there.
- **Map style** switches between standard, hybrid and satellite, all with realistic terrain.
- Trace can become the **default app for GPX files**: accept the offer shown on first launch, or choose *Trace › Make Trace the Default GPX App…* any time.

## Layout

```
Trace/
  TraceApp.swift          DocumentGroup scene, menu commands
  GPXDocument.swift       FileDocument for com.topografix.gpx
  DefaultHandler.swift    NSWorkspace default-app registration
  Playback.swift          Observable replay clock
  Model/
    GPXParser.swift       Streaming XMLParser for GPX 1.0/1.1 (trk, rte, wpt)
    TrackBuilder.swift    Distance, smoothed speed, stats, moment detection
    Track.swift           Analysed track, interpolation, speed-band runs
    Format.swift          Locale-aware formatting
  Views/
    TrackView.swift       Window shell: overlays, toolbar, default-handler offer
    MapStage.swift        MKMapView stage: gradient track, rider, flyover camera (imperative, per-frame)
    StatsCard.swift       Ride summary
    MomentsCard.swift     Moment list
    TimelinePanel.swift   Transport, speed chart scrubber, readout
    SpeedPalette.swift    Slow→fast colour ramp
```

## Smooth playback

Playback is driven by a `CADisplayLink`, and every per-frame update (camera, rider marker, playhead, readout) bypasses SwiftUI diffing: the map is an `MKMapView` updated imperatively, the chart is static with a separate playhead overlay, and the shell view never reads the playhead. The flyover camera follows a denoised copy of the track (triangular moving average over ±8 s, heading from a ±6 s window) with time-based low-pass filters, so GPS jitter and polyline corners don't shake the view. Measured on the sample ride: 60 Hz with no dropped frames.

Environment variables for testing: `TRACE_AUTOPLAY=0.45` starts playback at 45 % of the ride; `TRACE_SEEK=0.2` seeks without playing; `TRACE_FLYOVER=0` starts with flyover off; `TRACE_APPEARANCE=dark|light` forces the appearance; `TRACE_CAMLOG=1` logs requested and reported camera positions to stderr.

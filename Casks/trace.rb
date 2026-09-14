cask "trace" do
  version "1.0"
  sha256 "b4b7bf82646ab037c717e6ba783ef3c7de5c319fb7dd196abcddc903b4ba4c86"

  url "https://github.com/ljack/macos-gpx-viewer/releases/download/v#{version}/Trace-#{version}.zip"
  name "Trace"
  desc "Native GPX viewer with speed-coloured tracks and flyover replay"
  homepage "https://github.com/ljack/macos-gpx-viewer"

  depends_on macos: :tahoe

  app "Trace.app"

  zap trash: [
    "~/Library/Containers/fi.lietolahti.Trace",
    "~/Library/Preferences/fi.lietolahti.Trace.plist",
    "~/Library/Saved Application State/fi.lietolahti.Trace.savedState",
  ]
end

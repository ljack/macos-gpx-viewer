cask "trace" do
  version "1.2"
  sha256 "c0ae48aa4d6988fe98e8fa101f976303bcbc3beb33e1066da0549b14ca53c9e5"

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

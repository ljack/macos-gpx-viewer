cask "trace" do
  version "1.1"
  sha256 "8e0e6cb6e22a301384c8d27760d6ba8ef2d7c5e3683af62eb7223ba06e901c41"

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

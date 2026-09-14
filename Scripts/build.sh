#!/bin/zsh
# Release build → build/Trace.app. Add --install to copy it to /Applications.
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate >/dev/null
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Release -derivedDataPath build/DerivedData build | grep -E "error|BUILD" || true
rm -rf build/Trace.app
ditto build/DerivedData/Build/Products/Release/Trace.app build/Trace.app
echo "→ build/Trace.app"
if [[ "${1:-}" == "--install" ]]; then
  rm -rf /Applications/Trace.app
  ditto build/Trace.app /Applications/Trace.app
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/Trace.app
  echo "→ installed to /Applications/Trace.app"
fi

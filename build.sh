#!/bin/zsh
# Builds Text Tool.app into ./build. Usage: ./build.sh [--install]
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Text Tool.app"

swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/TextTool"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/TextTool"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"

# Ad-hoc sign so macOS will run it locally.
codesign --force --sign - --options runtime "$APP"
echo "Built: $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x TextTool 2>/dev/null || true
  rm -rf "/Applications/Text Tool.app"
  cp -R "$APP" /Applications/
  open "/Applications/Text Tool.app"
  echo "Installed to /Applications and launched."
fi

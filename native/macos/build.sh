#!/usr/bin/env bash
# Build the macOS SwiftUI render backend, packaged as a .app bundle so it can be
# launched into the user's GUI session with `open` (a bare executable launched
# from a detached shell never attaches to the window server).
set -euo pipefail
cd "$(dirname "$0")"

APP="RectRenderer.app"
BIN="$APP/Contents/MacOS/rect_renderer"
mkdir -p "$APP/Contents/MacOS"

swiftc main.swift -o "$BIN" \
  -framework AppKit -framework SwiftUI -framework Network

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>RectRenderer</string>
  <key>CFBundleDisplayName</key><string>Rect</string>
  <key>CFBundleIdentifier</key><string>space.sixfold.rect.renderer</string>
  <key>CFBundleExecutable</key><string>rect_renderer</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>0.1.0</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

echo "built bundle: $(pwd)/$APP"
echo "run: open $(pwd)/$APP --env RECT_PORT=8137"

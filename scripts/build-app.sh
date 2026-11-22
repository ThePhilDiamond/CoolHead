#!/bin/bash
# Builds "Cool Head.app" into build/, ad-hoc signed, from a clean checkout.
# Needs macOS 14 or later and the Xcode Command Line Tools; Xcode itself is not required.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(cat VERSION)
grep -q "version = \"$VERSION\"" Sources/CoolHeadCore/CaseReport.swift || { echo "VERSION ($VERSION) and CoolHead.version in CaseReport.swift differ"; exit 1; }
APP="build/Cool Head.app"

swift build -c release --product CoolHeadApp
swift build -c release --product coolhead
swift build -c release --product coolhead-chrome-host
BIN=$(swift build -c release --show-bin-path)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
cp "$BIN/CoolHeadApp" "$APP/Contents/MacOS/Cool Head"
cp "$BIN/coolhead" "$APP/Contents/MacOS/coolhead"
# Cool Head for Chrome's native messaging host, which Chrome starts by this path (Extension/chrome/PROTOCOL.md);
# codesign --deep below signs it with the app, as it signs Contents/MacOS/coolhead
cp "$BIN/coolhead-chrome-host" "$APP/Contents/Helpers/coolhead-chrome-host"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Cool Head</string>
  <key>CFBundleDisplayName</key><string>Cool Head</string>
  <key>CFBundleIdentifier</key><string>io.github.thephildiamond.coolhead</string>
  <key>CFBundleExecutable</key><string>Cool Head</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>Copyright © 2026 Phil Diamond. Free and open source under the GNU AGPL v3.0 only.</string>
</dict>
</plist>
PLIST
codesign --force --deep --sign - "$APP"
echo "Built $APP (version $VERSION)"

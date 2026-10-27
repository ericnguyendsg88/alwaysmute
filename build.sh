#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
APP="$PWD/AlwaysMute.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -target "$(uname -m)-apple-macosx13.0" -swift-version 5 -framework AppKit -framework CoreAudio -framework ServiceManagement Source/*.swift -o "$APP/Contents/MacOS/AlwaysMute"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>AlwaysMute</string>
<key>CFBundleIdentifier</key><string>local.QuietGuard</string>
<key>CFBundleIconFile</key><string>AlwaysMute</string>
<key>CFBundleName</key><string>AlwaysMute</string>
<key>CFBundleDisplayName</key><string>AlwaysMute</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSAudioCaptureUsageDescription</key><string>AlwaysMute uses this to set a separate volume for each app. Audio stays on your Mac.</string>
</dict></plist>
PLIST
ICONSET="$PWD/.build/AlwaysMute.iconset"
mkdir -p "$ICONSET"
"$APP/Contents/MacOS/AlwaysMute" --export-icon "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AlwaysMute.icns"
xattr -cr "$APP"
codesign --force --sign - "$APP"
echo "Built $APP"

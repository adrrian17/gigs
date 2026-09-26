#!/bin/sh
# Builds Gigs.app and installs it into /Applications.
set -e
cd "$(dirname "$0")"

swift build -c release
app=/Applications/Gigs.app
pkill -x Gigs || true
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp .build/release/Gigs "$app/Contents/MacOS/"
cat > "$app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>local.gigs</string>
    <key>CFBundleName</key><string>Gigs</string>
    <key>CFBundleExecutable</key><string>Gigs</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>CFBundleIconFile</key><string>AppIcon</string>
</dict>
</plist>
EOF
iconset=$(mktemp -d)/AppIcon.iconset
mkdir -p "$iconset"
sips -z 16 16 Assets/icon.png --out "$iconset/icon_16x16.png" >/dev/null
sips -z 32 32 Assets/icon.png --out "$iconset/icon_16x16@2x.png" >/dev/null
sips -z 32 32 Assets/icon.png --out "$iconset/icon_32x32.png" >/dev/null
sips -z 64 64 Assets/icon.png --out "$iconset/icon_32x32@2x.png" >/dev/null
sips -z 128 128 Assets/icon.png --out "$iconset/icon_128x128.png" >/dev/null
sips -z 256 256 Assets/icon.png --out "$iconset/icon_128x128@2x.png" >/dev/null
sips -z 256 256 Assets/icon.png --out "$iconset/icon_256x256.png" >/dev/null
sips -z 512 512 Assets/icon.png --out "$iconset/icon_256x256@2x.png" >/dev/null
sips -z 512 512 Assets/icon.png --out "$iconset/icon_512x512.png" >/dev/null
sips -z 1024 1024 Assets/icon.png --out "$iconset/icon_512x512@2x.png" >/dev/null
mkdir -p "$app/Contents/Resources"
iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"
rm -rf "$(dirname "$iconset")"
codesign --force --sign - "$app"

agent="$HOME/Library/LaunchAgents/local.gigs.plist"
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$agent" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>local.gigs</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Applications/Gigs.app/Contents/MacOS/Gigs</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>ProcessType</key>
    <string>Interactive</string>
    <key>LimitLoadToSessionType</key>
    <string>Aqua</string>
</dict>
</plist>
EOF
uid=$(id -u)
launchctl bootout "gui/$uid/local.gigs" 2>/dev/null || true
launchctl bootstrap "gui/$uid" "$agent" || open "$app"

#!/bin/sh
# Builds a universal Gigs.app and Gigs.dmg into .build/.
set -e
cd "$(dirname "$0")"
# Version from $VERSION, else the latest tag (v1.2.3 -> 1.2.3).
version=${VERSION:-$(git describe --tags --abbrev=0 2>/dev/null || echo 0.0.0)}
version=${version#v}

swift build -c release --arch arm64 --arch x86_64
app=.build/Gigs.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/apple/Products/Release/Gigs "$app/Contents/MacOS/"
cp -R Mole "$app/Contents/Resources/Mole"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>local.gigs</string>
    <key>CFBundleName</key><string>Gigs</string>
    <key>CFBundleShortVersionString</key><string>$version</string>
    <key>CFBundleVersion</key><string>$version</string>
    <key>CFBundleExecutable</key><string>Gigs</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>CFBundleIconFile</key><string>AppIcon</string>
</dict>
</plist>
PLIST
iconset=$(mktemp -d)/AppIcon.iconset
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
    sips -z $size $size Assets/icon.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) Assets/icon.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"
rm -rf "$(dirname "$iconset")"
codesign --force --sign - "$app"

stage=$(mktemp -d)
cp -R "$app" "$stage/"
ln -s /Applications "$stage/Applications"
rm -f .build/Gigs.dmg
hdiutil create -quiet -volname Gigs -srcfolder "$stage" -format UDZO .build/Gigs.dmg
rm -rf "$stage"
echo "Built .build/Gigs.dmg ($version)"

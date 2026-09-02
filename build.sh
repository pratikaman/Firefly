#!/bin/bash
# Build Firefly.app and (with --install) copy it to ~/Applications.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Firefly.app"
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -parse-as-library Sources/*.swift -o "$APP/Contents/MacOS/Firefly"
cp Info.plist "$APP/Contents/Info.plist"

# App icon, generated from assets/icon.png so the PNG stays the single source of
# truth and no .icns blob has to live in the repo.
ICONSET="build/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z $size $size assets/icon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) assets/icon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

codesign --force -s - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    mkdir -p ~/Applications
    rm -rf ~/Applications/Firefly.app
    cp -R "$APP" ~/Applications/
    # Nudge Finder so it doesn't keep showing the old cached icon.
    touch ~/Applications/Firefly.app
    echo "Installed to ~/Applications/Firefly.app"
fi

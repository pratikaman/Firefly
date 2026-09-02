#!/bin/bash
# Build Firefly.app and (with --install) copy it to ~/Applications.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Firefly.app"
rm -rf build
mkdir -p "$APP/Contents/MacOS"

swiftc -O -parse-as-library Sources/*.swift -o "$APP/Contents/MacOS/Firefly"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force -s - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    mkdir -p ~/Applications
    rm -rf ~/Applications/Firefly.app
    cp -R "$APP" ~/Applications/
    echo "Installed to ~/Applications/Firefly.app"
fi

#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
chrome="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
mkdir -p build/board-png
for appearance in light dark; do
    for frame in sign-in-none sign-in-wrong sign-in-locked sign-in-server banners controls; do
        case "$frame" in
            banners) height=1900 ;;
            controls) height=1200 ;;
            *) height=812 ;;
        esac
        name="$frame-$appearance"
        "$chrome" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=3 \
            --window-size="375,$height" --screenshot="build/board-png/$name.png" \
            "file://$PWD/_design/frames/auth/$name.html"
    done
done

#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
chrome="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
mkdir -p build/board-png
for appearance in light dark; do
    for frame in sign-in-none sign-in-wrong sign-in-locked sign-in-server two-factor-code-none two-factor-code-field two-factor-code-attempts two-factor-code-server two-factor-recovery-none two-factor-recovery-attempts two-factor-recovery-server forgot-none forgot-sent forgot-field forgot-attempts forgot-server banners controls; do
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

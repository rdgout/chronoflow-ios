#!/bin/sh
# iOS never prunes the lock-screen wallpaper snapshot cache in the simulator, and every
# appearance or text-size change adds snapshots (about 14 GB on 17e in four days).
set -eu

devices="$HOME/Library/Developer/CoreSimulator/Devices"

if pgrep -qf 'xcodebuild.*test'; then
    echo "sim-clean: a test run is in progress; try again when it finishes." >&2
    exit 1
fi

echo "Simulators before: $(du -sh "$devices" | cut -f1)"
xcrun simctl shutdown all >/dev/null 2>&1 || true
xcrun simctl erase all
xcrun simctl delete unavailable
echo "Simulators after:  $(du -sh "$devices" | cut -f1)"

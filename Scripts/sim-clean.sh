#!/bin/sh
# iOS never prunes the lock-screen wallpaper snapshot cache in the simulator, and every
# appearance or text-size change adds snapshots (about 14 GB on 17e in four days).
set -eu

devices="$HOME/Library/Developer/CoreSimulator/Devices"

# Erasing while a test clone runs invalidates the runtime's shared dyld cache: the clone's app
# crashes with SIGBUS and every relaunch fails with "no dyld cache" (2026-11-10).
if pgrep -qf 'xcodebuild.*test' || xcrun simctl --set testing list devices booted 2>/dev/null | grep -q Booted; then
    echo "sim-clean: a test run or test clone is active; try again when it finishes." >&2
    exit 1
fi

echo "Simulators before: $(du -sh "$devices" | cut -f1)"
xcrun simctl shutdown all >/dev/null 2>&1 || true
xcrun simctl erase all
xcrun simctl delete unavailable
xcrun simctl runtime dyld_shared_cache update --all >/dev/null
echo "Simulators after:  $(du -sh "$devices" | cut -f1)"

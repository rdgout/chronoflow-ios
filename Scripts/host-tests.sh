#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build/tmp build/SwiftPMHome
export TMPDIR="$PWD/build/tmp"
export CLANG_MODULE_CACHE_PATH="$PWD/build/ModuleCache"
export CFFIXED_USER_HOME="$PWD/build/SwiftPMHome"
swift test --disable-sandbox --package-path Packages/ChronoFlowKit \
    --scratch-path build/Phase9aHost --cache-path "$PWD/build/SwiftPMCache" \
    --config-path "$PWD/build/SwiftPMConfig" --security-path "$PWD/build/SwiftPMSecurity" \
    --triple arm64-apple-macosx14.0 "$@"

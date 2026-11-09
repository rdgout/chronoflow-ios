#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
action="$1"
package="$2"
shift 2
mkdir -p build/tmp build/SwiftPMHome
export TMPDIR="$PWD/build/tmp"
export CLANG_MODULE_CACHE_PATH="$PWD/build/ModuleCache"
export CFFIXED_USER_HOME="$PWD/build/SwiftPMHome"
if [ "$package" = ChronoFlowKit ]; then
    package_path="Packages/ChronoFlowKit"
    set -- --triple "$(uname -m)-apple-macosx14.0" "$@"
else
    package_path="Tools/$package"
fi
swift "$action" --disable-sandbox --package-path "$package_path" \
    --scratch-path "build/$package" --cache-path "$PWD/build/SwiftPMCache" \
    --config-path "$PWD/build/SwiftPMConfig" --security-path "$PWD/build/SwiftPMSecurity" "$@"

#!/bin/sh
set -eu
exec sh "$(dirname "$0")/swiftpm.sh" test ChronoFlowKit "$@"

#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build/tmp build/pip-cache
export TMPDIR="$PWD/build/tmp"
export PIP_CACHE_DIR="$PWD/build/pip-cache"
venv="$PWD/build/fonttools-venv"
if [ ! -x "$venv/bin/python3" ]; then python3 -I -m venv "$venv"; fi
if ! "$venv/bin/python3" -I -c 'import fontTools, brotli; assert fontTools.__version__ == "4.60.1"; assert brotli.__version__ == "1.1.0"' 2>/dev/null; then
    "$venv/bin/python3" -I -m pip install --disable-pip-version-check fonttools==4.60.1 brotli==1.1.0
fi
"$venv/bin/python3" -I Tools/generate_fonts.py "$@"

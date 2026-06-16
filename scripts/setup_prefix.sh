#!/usr/bin/env bash
set -euo pipefail

WSTEAM_DIR="$HOME/.wsteam"
WINE_DIR="$WSTEAM_DIR/wine"
PREFIX="$WSTEAM_DIR/prefix"

WINE_BIN="$WINE_DIR/bin/wine64"
if [ ! -f "$WINE_BIN" ]; then
    WINE_BIN="$WINE_DIR/bin/wine"
fi

if [ ! -f "$WINE_BIN" ]; then
    echo "ERROR: Wine not installed. Run install_wine.sh first."
    exit 1
fi

export WINEPREFIX="$PREFIX"
export WINEARCH="win64"
export WINEDEBUG="-all"

mkdir -p "$PREFIX"

echo "Initializing Wine prefix (Windows 10, 64-bit)..."
"$WINE_BIN" wineboot --init

echo "Setting Windows version to Win10..."
"$WINE_BIN" winecfg -v win10

echo "Prefix ready at $PREFIX"

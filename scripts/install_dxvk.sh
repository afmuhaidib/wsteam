#!/usr/bin/env bash
set -euo pipefail

WSTEAM_DIR="$HOME/.wsteam"
DXVK_DIR="$WSTEAM_DIR/dxvk"
PREFIX="$WSTEAM_DIR/prefix"
WINE_DIR="$WSTEAM_DIR/wine"

DXVK_VERSION="1.10.3-20230507-repack"
DXVK_URL="https://github.com/Gcenx/DXVK-macOS/releases/download/v1.10.3-20230507-repack/dxvk-macOS-async-v1.10.3-20230507-repack.tar.gz"
ARCHIVE="$WSTEAM_DIR/dxvk.tar.gz"

mkdir -p "$DXVK_DIR"

echo "Downloading DXVK $DXVK_VERSION for macOS..."
curl -L --progress-bar -o "$ARCHIVE" "$DXVK_URL"

echo "Extracting..."
tar -xzf "$ARCHIVE" -C "$WSTEAM_DIR"

EXTRACTED="$WSTEAM_DIR/dxvk-macOS-async-v1.10.3-20230507-repack"
if [ -d "$EXTRACTED" ]; then
    rm -rf "$DXVK_DIR"
    mv "$EXTRACTED" "$DXVK_DIR"
fi
rm -f "$ARCHIVE"

echo "Installing DXVK into prefix..."
SYS32="$PREFIX/drive_c/windows/system32"
SYSWOW="$PREFIX/drive_c/windows/syswow64"
mkdir -p "$SYS32" "$SYSWOW"

for dll in d3d9 d3d10core d3d11 dxgi; do
    [ -f "$DXVK_DIR/x64/${dll}.dll" ] && cp "$DXVK_DIR/x64/${dll}.dll" "$SYS32/"
    [ -f "$DXVK_DIR/x32/${dll}.dll" ] && cp "$DXVK_DIR/x32/${dll}.dll" "$SYSWOW/"
done

WINE_BIN="$WINE_DIR/bin/wine64"
[ ! -f "$WINE_BIN" ] && WINE_BIN="$WINE_DIR/bin/wine"

export WINEPREFIX="$PREFIX"
export WINEDEBUG="-all"

for dll in d3d9 d3d10core d3d11 dxgi; do
    "$WINE_BIN" reg add \
        "HKEY_CURRENT_USER\Software\Wine\DllOverrides" \
        /v "$dll" /d "native,builtin" /f 2>/dev/null || true
done

echo "DXVK installed!"

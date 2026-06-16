#!/usr/bin/env bash
set -euo pipefail

WSTEAM_DIR="$HOME/.wsteam"
WINE_DIR="$WSTEAM_DIR/wine"

mkdir -p "$WSTEAM_DIR"

if [ -f "$WINE_DIR/bin/wine64" ] || [ -f "$WINE_DIR/bin/wine" ]; then
    echo "Wine already installed at $WINE_DIR"
    exit 0
fi

VERSION="24.0.2"
URL="https://github.com/Gcenx/macOS_Wine_builds/releases/download/${VERSION}/wine-crossover-${VERSION}-osx64.tar.xz"
ARCHIVE="$WSTEAM_DIR/wine.tar.xz"

echo "Downloading Wine Crossover $VERSION..."
curl -L --progress-bar -o "$ARCHIVE" "$URL"

echo "Extracting..."
tar -xJf "$ARCHIVE" -C "$WSTEAM_DIR"

# Rename extracted dir
EXTRACTED="$WSTEAM_DIR/wine-crossover-${VERSION}"
if [ -d "$EXTRACTED" ]; then
    mv "$EXTRACTED" "$WINE_DIR"
fi

rm -f "$ARCHIVE"
echo "Wine installed to $WINE_DIR"

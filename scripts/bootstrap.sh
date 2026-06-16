#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== wsteam bootstrap ==="
echo "This script sets up everything needed to run Windows Steam games."
echo ""

bash "$DIR/install_wine.sh"
bash "$DIR/setup_prefix.sh"
bash "$DIR/install_dxvk.sh"

WSTEAM_DIR="$HOME/.wsteam"
WINE_DIR="$WSTEAM_DIR/wine"
PREFIX="$WSTEAM_DIR/prefix"
STEAM_URL="https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe"
INSTALLER="$WSTEAM_DIR/SteamSetup.exe"
WINE_BIN="$WINE_DIR/bin/wine64"
[ ! -f "$WINE_BIN" ] && WINE_BIN="$WINE_DIR/bin/wine"

echo ""
echo "Downloading Steam installer..."
curl -L --progress-bar -o "$INSTALLER" "$STEAM_URL"

echo "Running Steam installer (a Windows dialog will appear)..."
export WINEPREFIX="$PREFIX"
export WINEDEBUG="-all"
export DXVK_ASYNC=1
"$WINE_BIN" "$INSTALLER" /S

echo ""
echo "=== Bootstrap complete! ==="
echo "Run 'wsteamd &' then 'wsteam steam' to open Steam."

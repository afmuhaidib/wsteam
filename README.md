# wsteam

Run Windows Steam games on macOS — like CrossOver, but open source and for personal use.

**Works on:** macOS 14+ (Apple Silicon via Rosetta 2, Intel native)

## What It Does

- Downloads Wine Crossover (best Steam compat)
- Creates a Windows 10 64-bit prefix
- Installs Steam for Windows inside Wine
- Sets up DXVK (DirectX → Vulkan) + MoltenVK (Vulkan → Metal)
- Provides a SwiftUI game library + CLI

## Install

```bash
git clone https://github.com/24temprature/wsteam
cd wsteam
make all
make install      # installs wsteam + wsteamd to /usr/local/bin
```

## Usage

```bash
# One-time setup (~1 GB download)
wsteamd &
wsteam setup

# Open Steam (log in and download games here)
wsteam steam

# List installed games
wsteam list

# Launch Among Us (App ID 945360)
wsteam launch 945360

# Status
wsteam status
```

Or open `build/wsteam.app` for the GUI.

## Tech Stack

| Layer | Tech |
|-------|------|
| Compatibility | Wine Crossover 24 (gcenx) |
| DirectX translation | DXVK 2.5 |
| Vulkan on Metal | MoltenVK 1.2 |
| Core engine | Rust + Tokio |
| IPC | Unix socket (JSON) |
| UI | Swift / SwiftUI |
| Scripts | Bash |

## No signing required

Built for personal use — no App Store, no notarization.
If macOS blocks the app: System Settings → Privacy → Allow.

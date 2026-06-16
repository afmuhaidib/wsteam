# wsteam

Run Windows Steam games on macOS via Wine + DXVK + MoltenVK.

## Architecture

| Component | Language | Role |
|-----------|----------|------|
| `crates/wsteam-core` | Rust | Core library: Wine, prefix, Steam, DXVK management |
| `crates/wsteam-daemon` | Rust (Tokio) | Unix-socket IPC daemon (`wsteamd`) |
| `crates/wsteam-cli` | Rust | CLI tool (`wsteam`) |
| `ui/` | Swift/SwiftUI | macOS app |
| `scripts/` | Bash | Bootstrap/setup helpers |

## Quick Start

```bash
# One-time setup (downloads Wine, Steam, DXVK — ~1 GB)
./scripts/bootstrap.sh

# Or via CLI (requires daemon running)
wsteamd &
wsteam setup
wsteam steam         # open Steam
wsteam launch 945360 # launch Among Us
```

## Build

```bash
make all        # build Rust + Swift + bundle app
make install    # install wsteam + wsteamd to /usr/local/bin
make test       # run Rust tests
```

## How It Works

1. **Wine Crossover** (gcenx build) provides a Windows compatibility layer on macOS ARM via Rosetta 2.
2. **Wine prefix** at `~/.wsteam/prefix` holds a Windows 10 64-bit environment.
3. **Steam for Windows** runs inside the prefix — log in, download games normally.
4. **DXVK** translates DirectX 9/10/11 → Vulkan; **MoltenVK** translates Vulkan → Metal.
5. Games launch via `wsteam launch <APPID>` or from the SwiftUI library.

## Data Layout

```
~/.wsteam/
  config.toml     # config + game library
  wine/           # Wine Crossover binaries
  prefix/         # Windows prefix (drive_c/ etc.)
  dxvk/           # DXVK DLLs (x32/ x64/)
  MoltenVK/       # MoltenVK dylib + ICD JSON
  SteamSetup.exe  # Steam installer (deleted after use)
```

## IPC Protocol

Daemon listens on `/tmp/wsteam.sock`. Protocol: newline-delimited JSON.

Commands: `GetStatus`, `SetupWine`, `SetupSteam`, `SetupDxvk`, `FullSetup`,
`LaunchSteam`, `LaunchGame`, `ScanLibrary`, `KillWineserver`, `Shutdown`.

## Notes

- No app signing (personal use only)
- Requires macOS 14+ (Sonoma) and Rosetta 2 for x86 Windows games on Apple Silicon
- Enable Rosetta: `softwareupdate --install-rosetta`

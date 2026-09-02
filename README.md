<div align="center">

<img src="resources/whale-harness.png" alt="DeepSeek Harness macOS Launcher" width="160" />

# DeepSeek Harness Launcher for macOS

**A minimal status-bar application for launching, restarting, and controlling [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness), written in Swift.**

[![Release](https://img.shields.io/github/v/release/deep-blue-dark-red/deepseek-harness-launcher-for-macos?logo=github&label=Release&color=blue)](https://github.com/deep-blue-dark-red/deepseek-harness-launcher-for-macos/releases/latest)
[![macOS](https://img.shields.io/badge/macOS-13.0%2B-blue?logo=apple&logoColor=white)](https://apple.com/macos)
[![Swift](https://img.shields.io/badge/Swift-Native%20AppKit-orange?logo=swift&logoColor=white)](https://swift.org)
[![Architecture](https://img.shields.io/badge/Architecture-Apple%20Silicon%20%7C%20Intel-purple)]()
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](https://opensource.org/licenses/MIT)

<br />

<img src="resources/desktop-macos.png" alt="DeepSeek Harness macOS Launcher Screenshot" width="850" />

</div>

---

## Installation

Run the end-to-end installer:

```bash
git clone https://github.com/deep-blue-dark-red/deepseek-harness-launcher-for-macos
cd deepseek-harness-launcher-for-macos
./install.sh
```

Once installed, launch **DeepSeek Harness Launcher** via:
- **Spotlight / Raycast**: Press `Cmd + Space`, type `DeepSeek Harness Launcher`, and press `Enter`.
- **Finder / Launchpad**: Open `~/Applications/DeepSeek Harness Launcher.app`.
- **Terminal**: `open -a "DeepSeek Harness Launcher"`

## Uninstallation

To remove the application and stop background processes:

```bash
./uninstall.sh
```

---

## Overview

**DeepSeek Harness Launcher** (`DeepSeek Harness Launcher.app`) is a lightweight native macOS AppKit application designed to launch, control, and monitor DeepSeek Harness servers, web interfaces, interactive terminal sessions, and headless tasks directly from your macOS Menu Bar, Dock, Spotlight, Raycast, or Launchpad.

---

## Features

- 🐋 **Menu Bar & Status Item**: Instant access from the macOS menu bar (🐋 DSH when running, 🐙 DSH when stopped) with live status indicators (🔵 Running, 🟡 Starting, ⚪ Stopped).
- **Central Control Window**: High-resolution GUI panel displaying active workspace, server state, quick action buttons, and configuration options.
- **Interactive Terminal Session**: Opens a native terminal window pre-configured with workspace paths, `$PATH` discovery, and active API credentials.
- **Headless Task Launcher**: Run ad-hoc AI tasks on demand (`dsh --profile headless "<task>"`) with a native prompt dialog.
- **Live Log Viewer**: Dedicated console window displaying real-time streaming server logs and historical output, with copy, clear, and direct log file opening.
- **Smart Environment Discovery**: Automatically locates `node` (>= 22.19.0) and `pnpm` across Homebrew (`/opt/homebrew`, `/usr/local`), `nvm`, `asdf`, `proto`, `fnm`, and `volta`.
- **Secure Key Management**: Prompt and store `DEEPSEEK_API_KEY` securely in `~/.dsh/.env` or repository `.env`.
- **Server Startup & Clean Teardown**: DeepSeek-Harness runs as a managed child process; killing DSHL also tears down the child server process cleanly, mitigating the need for console commands entirely. No terminal process is started (hidden, with output streamable via *View Live Logs*). Session states are preserved.
- **Zero Telemetry & Private**: No analytics, telemetry, or third-party network calls. I wrote this for my own usage for quick launching via Raycast, Spotlight, or menu bar.

---

## Repository Structure

```
deepseek-harness-launcher-for-macos/
├── install.sh                  # End-to-end installation script
├── uninstall.sh                # Clean uninstallation script
├── Info.plist                  # macOS Application bundle metadata & permissions
├── Makefile                    # Make targets (build, install, uninstall, clean)
├── dsh-launcher.command        # Double-clickable macOS Finder script
├── resources/
│   ├── AppIcon.icns            # Multi-resolution Retina icon bundle (16x16 to 1024x1024)
│   ├── desktop-macos.png       # High-resolution desktop UI screenshot
│   ├── whale-harness.png       # High-resolution logo artwork
│   └── favicon.svg             # Vector icon asset
├── src/
│   └── main.swift              # Native Swift AppKit Launcher implementation
└── scripts/
    ├── build.sh                # Compiles swift source and bundles DeepSeek Harness Launcher.app
    ├── generate-icon.sh        # Generates soft-corner squircle .icns from artwork
    └── install.sh              # Bundle installer helper
```

---

## Build Targets

```bash
make install     # Build and install to ~/Applications/DeepSeek Harness Launcher.app
make uninstall   # Stop running instances and remove application
make build       # Compile and bundle dist/DeepSeek Harness Launcher.app
make run         # Build and launch application immediately
make icon        # Regenerate AppIcon.icns from resources/whale-harness.png
make clean       # Remove build outputs and cached artifacts
```

---

## System Requirements

- **Operating System**: macOS 13.0 (Ventura) or newer (Sonoma, Sequoia).
- **Architectures**: Apple Silicon (`arm64`) and Intel (`x86_64`).
- **Launcher Dependencies**:
  - **Prebuilt Binary**: None (pure native Swift/AppKit, zero runtime dependencies).
  - **Building from Source**: Xcode Command Line Tools (`swiftc` via `xcode-select --install`) and `make`.
- **Target Workload**: A local clone of [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) (the launcher automatically discovers `node` and `pnpm` across Homebrew, nvm, asdf, proto, fnm, and volta).

---

## License

Distributed under the MIT License.

<div align="center">

<img src="resources/whale-harness.png" alt="DeepSeek Harness macOS Launcher" width="180" />

# DeepSeek Harness Launcher for macOS

**A minimal status-bar application for launching, restarting, and controlling [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness), written in Swift.**

[![macOS](https://img.shields.io/badge/macOS-13.0%2B-blue?logo=apple&logoColor=white)](https://apple.com/macos)
[![Swift](https://img.shields.io/badge/Swift-Native%20AppKit-orange?logo=swift&logoColor=white)](https://swift.org)
[![Architecture](https://img.shields.io/badge/Architecture-Apple%20Silicon%20%7C%20Intel-purple)]()
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](https://opensource.org/licenses/MIT)

</div>

---

## 🌟 Overview

**DeepSeek Harness Launcher** (`DeepSeek Harness.app`) is a lightweight, zero-overhead native macOS AppKit application designed to seamlessly launch, control, and monitor DeepSeek Harness servers, web interfaces, interactive terminal sessions, and headless tasks directly from your macOS Menu Bar, Dock, Spotlight, or Launchpad.

---

## ✨ Features

- 🐋 **Menu Bar & Status Item**: Instant access from the macOS menu bar (`🐋 DSH`) with live status indicators (`🟢 Running`, `🟡 Starting`, `⚪ Stopped`).
- 🖥 **Central Control Window**: High-resolution GUI panel displaying active workspace, server state, quick action buttons, and configuration options.
- ⚡ **Interactive Terminal Session**: Opens a native terminal window pre-configured with workspace paths, `$PATH` discovery, and active API credentials.
- 🤖 **Headless Task Launcher**: Run ad-hoc AI tasks on demand (`dsh --profile headless "<task>"`) with a native prompt dialog.
- 📜 **Live Log Viewer**: Dedicated console window displaying real-time streaming server logs, historical logs, with search, copy, clear, and direct log file opening.
- 🔍 **Smart Environment Discovery**: Automatically locates `node` (>= 22.19.0) and `pnpm` across Homebrew (`/opt/homebrew`, `/usr/local`), `nvm`, `asdf`, `proto`, `fnm`, and `volta`.
- 🔑 **Secure Key Management**: Prompt and store `DEEPSEEK_API_KEY` securely in `~/.dsh/.env` or repository `.env`.
- 🛡 **Clean Lifecycle & Teardown**: Guarantees background Node and server processes are cleanly terminated upon exit.

---

## 🚀 Quick Start

### Installation

Clone the repository and run `make install`:

```bash
git clone https://github.com/deep-blue-dark-red/deepseek-harness-launcher-for-macos.git ~/git/deepseek-harness-launcher
cd ~/git/deepseek-harness-launcher
make install
```

Once installed, launch **DeepSeek Harness** via:
- **Spotlight**: Press `Cmd + Space`, type `DeepSeek Harness`, and press `Enter`.
- **Finder / Launchpad**: Open `~/Applications/DeepSeek Harness.app`.
- **Terminal CLI**: `open -a "DeepSeek Harness"`

---

## 🛠 Repository Structure

```
deepseek-harness-launcher/
├── Info.plist                  # macOS Application bundle metadata & permissions
├── Makefile                    # Make targets (build, install, icon, clean)
├── dsh-launcher.command        # Double-clickable macOS Finder script
├── resources/
│   ├── AppIcon.icns            # Multi-resolution Retina icon bundle (16x16 to 1024x1024)
│   ├── whale-harness.png       # High-resolution logo artwork
│   └── favicon.svg             # Vector icon asset
├── src/
│   └── main.swift              # Native Swift AppKit Launcher implementation
└── scripts/
    ├── build.sh                # Compiles swift source and bundles DeepSeek Harness.app
    ├── generate-icon.sh        # Generates soft-corner squircle .icns from artwork
    └── install.sh              # Installs bundle to ~/Applications/DeepSeek Harness.app
```

---

## 🔨 Build & Developer Targets

```bash
make build       # Compile and bundle dist/DeepSeek Harness.app
make install     # Build and install to ~/Applications/DeepSeek Harness.app
make run         # Build and launch application immediately
make icon        # Regenerate AppIcon.icns from resources/whale-harness.png
make clean       # Remove build outputs and cached artifacts
```

---

## 💻 System Requirements

- **Operating System**: macOS 13.0 (Ventura) or newer (Sonoma, Sequoia).
- **Architectures**: Apple Silicon (`arm64`) and Intel (`x86_64`).
- **Dependencies**: 
  - Node.js (`^22.19 || >=24`)
  - `pnpm`
  - Xcode Command Line Tools (`swiftc`)

---

## 👤 Author & Credits

Made by **[deep-blue-dark-red](https://github.com/deep-blue-dark-red/deepseek-harness-launcher-for-macos)**.
Distributed under the [MIT License](https://opensource.org/licenses/MIT).

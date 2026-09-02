# DeepSeek Harness macOS Launcher

Native macOS desktop controller and launcher suite for **[DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)**.

---

## Overview

`DeepSeek Harness.app` is a lightweight, high-performance native macOS AppKit application that manages and launches DeepSeek Harness servers, web interfaces, interactive terminal sessions, and headless tasks directly from the macOS Menu Bar, Dock, or Spotlight.

### Key Capabilities

- 🐋 **Status Bar & Menu Bar Item**: Start, stop, and monitor the `dsh web` server directly from the macOS status bar (`🐋 DSH`), with live status badges (`🟢 Running`, `🟡 Starting`, `Stopped`).
- 🖥 **Desktop Control Center**: Central dashboard displaying workspace path, server status, quick action buttons, and configuration options.
- ⚡ **Terminal Session Launcher**: Instantly launches an interactive shell terminal with pre-configured environment and `dsh` tools in `$PATH`.
- 🤖 **Headless Task Modal**: Prompt for a single task instruction via macOS dialog and execute `dsh --profile headless "<task>"`.
- 📜 **Live Log Viewer**: View real-time server output, requests, and diagnostics in a dedicated log console window.
- 🔍 **Smart Environment Discovery**: Automatically locates `node` (>= 22.19.0) and `pnpm` across Homebrew (`/opt/homebrew`, `/usr/local`), nvm, asdf, proto, fnm, and volta.
- 🔑 **API Key & Config Management**: Configure `DEEPSEEK_API_KEY` with secure persistence to `~/.dsh/.env` or repository `.env`.
- 🛡 **Clean Process Teardown**: Guarantees child Node processes are gracefully killed on exit to prevent orphaned processes on ports.

---

## Quick Start

### 1. Build and Install

```bash
# Clone and enter directory
cd /Users/mcp/git/deepseek-harness-launcher

# Build and install to ~/Applications
make install
```

Once installed, you can launch **DeepSeek Harness** at any time using:
- **Spotlight**: `Cmd + Space` → Type `DeepSeek Harness`
- **Launchpad** / **Finder**: Open `~/Applications/DeepSeek Harness.app`
- **CLI**: `open -a "DeepSeek Harness"`

### 2. Double-Click in Finder

You can also double-click `dsh-launcher.command` directly from Finder for an interactive terminal interface.

---

## Repository Structure

```
deepseek-harness-launcher/
├── Info.plist                  # macOS Application bundle metadata
├── Makefile                    # Build & installation targets (make, make install, make clean)
├── dsh-launcher.command        # Double-clickable macOS Finder terminal script
├── resources/
│   ├── AppIcon.icns            # High-resolution Retina icon bundle
│   └── favicon.svg             # Vector icon source
├── src/
│   └── main.swift              # Native Swift AppKit Launcher implementation
└── scripts/
    ├── build.sh                # Compiles swift source and bundles DeepSeek Harness.app
    ├── generate-icon.sh        # Converts SVG into multi-resolution .icns file
    └── install.sh              # Installs bundle to ~/Applications/DeepSeek Harness.app
```

---

## Build Targets

```bash
make build       # Compile and bundle dist/DeepSeek Harness.app
make install     # Build and install to ~/Applications
make run         # Build and launch immediately
make icon        # Regenerate AppIcon.icns from resources/favicon.svg
make clean       # Remove build artifacts
```

---

## System Requirements

- **macOS**: macOS 13.0 (Ventura) or newer (macOS Sonoma, macOS Sequoia)
- **Architecture**: Apple Silicon (`arm64`) & Intel (`x86_64`)
- **Dependencies**: Node.js (>= 22.19.0), pnpm, Xcode Command Line Tools (`swiftc`)

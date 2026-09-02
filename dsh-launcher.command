#!/usr/bin/env bash
# ==============================================================================
# DeepSeek Harness - macOS Terminal Launcher (.command)
# Double-clickable in macOS Finder or executable directly from Terminal.
# ==============================================================================

set -euo pipefail

# Determine script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# A DeepSeek-Harness checkout has both a package.json and apps/cli.
is_harness_root() {
    [ -n "${1:-}" ] && [ -f "${1}/package.json" ] && [ -d "${1}/apps/cli" ]
}

# Locate the harness checkout. This script may live inside the harness repo, next
# to it, or anywhere else (it ships in the launcher repo), so search rather than
# assuming a fixed relative depth.
find_harness_root() {
    local candidate

    # 1. Explicit override.
    if is_harness_root "${DSH_REPO_ROOT:-}"; then
        printf '%s' "${DSH_REPO_ROOT}"
        return 0
    fi

    # 2. Whatever folder the .app was pointed at, so both launchers agree.
    if command -v defaults &>/dev/null; then
        candidate="$(defaults read com.deepseek.harness.launcher DSH_REPO_ROOT 2>/dev/null || true)"
        if is_harness_root "${candidate}"; then
            printf '%s' "${candidate}"
            return 0
        fi
    fi

    # 3. This script's own directory, then each ancestor.
    candidate="${SCRIPT_DIR}"
    while [ "${candidate}" != "/" ]; do
        if is_harness_root "${candidate}"; then
            printf '%s' "${candidate}"
            return 0
        fi
        candidate="$(dirname "${candidate}")"
    done

    # 4. Conventional checkout locations (mirrors src/main.swift).
    for candidate in "${HOME}/git/deepseek-harness" "${HOME}/Projects/deepseek-harness" \
                     "${HOME}/Developer/deepseek-harness" "${HOME}/code/deepseek-harness" \
                     "${HOME}/deepseek-harness"; do
        if is_harness_root "${candidate}"; then
            printf '%s' "${candidate}"
            return 0
        fi
    done

    return 1
}

if ! REPO_ROOT="$(find_harness_root)"; then
    echo "Error: could not locate a DeepSeek-Harness checkout." >&2
    echo "Clone it, or point this script at it:" >&2
    echo "  DSH_REPO_ROOT=/path/to/deepseek-harness \"${BASH_SOURCE[0]}\"" >&2
    echo "" >&2
    read -rp "Press Enter to exit..."
    exit 1
fi

# Ensure common macOS binary locations are in PATH
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:${HOME}/.local/bin:${HOME}/.cargo/bin:${HOME}/.proto/shims:${HOME}/.proto/bin:${HOME}/.asdf/shims:${HOME}/.asdf/bin:${HOME}/.fnm/current/bin:${HOME}/.volta/bin:${PATH}"

# Look for nvm node versions if node is not found
if ! command -v node &>/dev/null; then
    if [ -d "${HOME}/.nvm/versions/node" ]; then
        LATEST_NVM_NODE="$(find "${HOME}/.nvm/versions/node" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -n 1)"
        if [ -n "${LATEST_NVM_NODE}" ] && [ -d "${LATEST_NVM_NODE}/bin" ]; then
            export PATH="${LATEST_NVM_NODE}/bin:${PATH}"
        fi
    fi
fi

# Color output helpers
BOLD='\033[1m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

clear || true

echo -e "${CYAN}${BOLD}"
echo "  ____                  ____            _      _   _                                "
echo " |  _ \  ___  ___ _ __ / ___|  ___  ___| | __ | | | | __ _ _ __ _ __   ___  ___ ___ "
echo " | | | |/ _ \/ _ \ '_ \\___ \ / _ \/ _ \ |/ / | |_| |/ _\` | '__| '_ \ / _ \/ __/ __|"
echo " | |_| |  __/  __/ |_) |___) |  __/  __/   <  |  _  | (_| | |  | | | |  __/\__ \__ \\"
echo " |____/ \___|\___| .__/|____/ \___|\___|_|\_\ |_| |_|\__,_|_|  |_| |_|\___||___/___/"
echo "                 |_|                                                                "
echo -e "${NC}"
echo -e "${BOLD}DeepSeek Harness — macOS Launcher${NC}"
echo "Workspace: ${REPO_ROOT}"
echo "--------------------------------------------------------------------------------"

# Pre-flight Checks
cd "${REPO_ROOT}"

# 1. Check Node & pnpm
if ! command -v node &>/dev/null; then
    echo -e "${RED}Error: Node.js is not found in PATH.${NC}"
    echo "Please install Node.js (>= 22.19.0) using Homebrew (brew install node) or nvm."
    echo ""
    read -rp "Press Enter to exit..."
    exit 1
fi

if ! command -v pnpm &>/dev/null; then
    echo -e "${RED}Error: pnpm is not found in PATH.${NC}"
    echo "Please install pnpm (corepack enable pnpm or brew install pnpm)."
    echo ""
    read -rp "Press Enter to exit..."
    exit 1
fi

NODE_VERSION="$(node -v)"
echo -e "Node: ${GREEN}${NODE_VERSION}${NC}  |  pnpm: ${GREEN}$(pnpm -v)${NC}"

# 2. Credentials are the harness's business, not this script's. DeepSeek Harness
#    resolves its own API key (its Providers page writes $DSH_HOME/.credentials.yaml,
#    and an ambient $DEEPSEEK_API_KEY is honoured). Nothing is read or stored here.

# 3. Check build artifacts
if [ ! -f "${REPO_ROOT}/apps/web/dist/index.html" ] || [ ! -d "${REPO_ROOT}/packages/core/session/lib" ]; then
    echo -e "${YELLOW}Building required packages and web frontend...${NC}"
    pnpm run build || true
fi

echo "--------------------------------------------------------------------------------"
echo -e "${BOLD}Select launch mode:${NC}"
echo "  1) 🌐 Web GUI (default - launches browser interface)"
echo "  2) 🤖 Headless Task (prompt for a single task and run)"
echo "  3) ⚡ Interactive Shell Session (open interactive agent terminal)"
echo "  4) 📜 View CLI Help"
echo "  5) 🔨 Rebuild Project Packages & Frontend"
echo "  q) Quit"
echo "--------------------------------------------------------------------------------"

read -rp "Choice [1-5, q] (default: 1): " CHOICE
CHOICE="${CHOICE:-1}"

case "${CHOICE}" in
    1)
        echo -e "${GREEN}Starting DeepSeek Harness Web GUI...${NC}"
        echo "Press Ctrl+C to stop the server."
        echo ""
        exec pnpm dsh web
        ;;
    2)
        echo ""
        read -rp "Enter task instruction: " TASK_PROMPT
        if [ -n "${TASK_PROMPT}" ]; then
            echo -e "${GREEN}Running headless task...${NC}"
            echo ""
            pnpm dsh --profile headless "${TASK_PROMPT}"
        else
            echo "Task was empty."
        fi
        echo ""
        read -rp "Press Enter to exit..."
        ;;
    3)
        echo -e "${GREEN}Starting Interactive Session...${NC}"
        echo "Tip: Run 'pnpm dsh --help' for all commands."
        echo ""
        exec "${SHELL:-/bin/zsh}" -l
        ;;
    4)
        pnpm dsh --help
        echo ""
        read -rp "Press Enter to exit..."
        ;;
    5)
        echo -e "${CYAN}Rebuilding packages and web frontend...${NC}"
        pnpm run build
        echo -e "${GREEN}Build complete!${NC}"
        echo ""
        read -rp "Press Enter to exit..."
        ;;
    q|Q)
        echo "Exiting."
        exit 0
        ;;
    *)
        echo -e "${RED}Invalid choice.${NC}"
        exit 1
        ;;
esac

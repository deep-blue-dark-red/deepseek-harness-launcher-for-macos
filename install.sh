#!/usr/bin/env bash
# ==============================================================================
# End-to-end installer for DeepSeek Harness Launcher for macOS
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST_DIR="${SCRIPT_DIR}/dist"
APP_BUNDLE="${DIST_DIR}/DeepSeek Harness.app"
TARGET_DIR="${HOME}/Applications"
TARGET_APP="${TARGET_DIR}/DeepSeek Harness.app"

BOLD='\033[1m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}${BOLD}=== Installing DeepSeek Harness Launcher for macOS ===${NC}"

# 1. Check prerequisites
if ! command -v swiftc &>/dev/null; then
    echo -e "${RED}Error: swiftc compiler not found.${NC}"
    echo "Please install Xcode Command Line Tools by running:"
    echo "  xcode-select --install"
    exit 1
fi

# 2. Build the application bundle
echo "Building application..."
"${SCRIPT_DIR}/scripts/build.sh"

# 3. Install to ~/Applications
echo "Installing to ${TARGET_DIR}..."
mkdir -p "${TARGET_DIR}"
rm -rf "${TARGET_APP}"
cp -R "${APP_BUNDLE}" "${TARGET_APP}"

echo -e "${GREEN}${BOLD}✓ DeepSeek Harness Launcher successfully installed to:${NC}"
echo "  ${TARGET_APP}"
echo ""
echo "Launch options:"
echo "  • Spotlight: Press Cmd + Space, type 'DeepSeek Harness', and press Enter"
echo "  • Launchpad / Finder: Open ~/Applications/DeepSeek Harness.app"
echo "  • Terminal: open -a \"DeepSeek Harness\""

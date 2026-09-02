#!/usr/bin/env bash
# ==============================================================================
# Uninstaller for DeepSeek Harness Launcher for macOS
# ==============================================================================

set -euo pipefail

TARGET_DIR="${HOME}/Applications"
TARGET_APP="${TARGET_DIR}/DeepSeek Harness.app"

BOLD='\033[1m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

echo -e "${CYAN}${BOLD}=== Uninstalling DeepSeek Harness Launcher ===${NC}"

# 1. Terminate running instance if active
if pgrep -f "DeepSeekHarnessLauncher" &>/dev/null; then
    echo "Stopping running DeepSeek Harness instance..."
    pkill -f "DeepSeekHarnessLauncher" 2>/dev/null || true
    sleep 1
fi

# 2. Remove application bundle
if [ -d "${TARGET_APP}" ]; then
    echo "Removing ${TARGET_APP}..."
    rm -rf "${TARGET_APP}"
    echo -e "${GREEN}${BOLD}✓ Removed ${TARGET_APP}${NC}"
else
    echo -e "${YELLOW}Notice: ${TARGET_APP} was not found.${NC}"
fi

echo -e "${GREEN}${BOLD}✓ DeepSeek Harness Launcher uninstalled successfully.${NC}"

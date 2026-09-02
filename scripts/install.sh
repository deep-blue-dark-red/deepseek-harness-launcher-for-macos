#!/usr/bin/env bash
# ==============================================================================
# Install DeepSeek Harness Launcher.app into ~/Applications
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DIST_DIR="${REPO_ROOT}/dist"
APP_BUNDLE="${DIST_DIR}/DeepSeek Harness Launcher.app"
TARGET_DIR="${HOME}/Applications"
TARGET_APP="${TARGET_DIR}/DeepSeek Harness Launcher.app"

BOLD='\033[1m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
NC='\033[0m'

# Build first if not present
if [ ! -d "${APP_BUNDLE}" ]; then
    "${SCRIPT_DIR}/build.sh"
fi

echo -e "${CYAN}Installing DeepSeek Harness Launcher.app to ${TARGET_DIR}...${NC}"
mkdir -p "${TARGET_DIR}"
rm -rf "${TARGET_APP}" "${TARGET_DIR}/DeepSeek Harness.app"
cp -R "${APP_BUNDLE}" "${TARGET_APP}"

echo -e "${GREEN}${BOLD}✓ DeepSeek Harness Launcher installed successfully to ${TARGET_APP}${NC}"
echo "You can now launch it via Spotlight (Cmd+Space), Launchpad, or ~/Applications."

#!/usr/bin/env bash
# ==============================================================================
# Build DeepSeek Harness.app macOS Application Bundle
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DIST_DIR="${REPO_ROOT}/dist"
APP_BUNDLE="${DIST_DIR}/DeepSeek Harness.app"
ICON_PATH="${REPO_ROOT}/resources/AppIcon.icns"
SRC_PATH="${REPO_ROOT}/src/main.swift"
PLIST_PATH="${REPO_ROOT}/Info.plist"

BOLD='\033[1m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}${BOLD}=== Building DeepSeek Harness for macOS ===${NC}"

if ! command -v swiftc &>/dev/null; then
    echo -e "${RED}Error: swiftc compiler not found.${NC}"
    echo "Please install Xcode Command Line Tools (xcode-select --install)."
    exit 1
fi

if [ ! -f "${ICON_PATH}" ]; then
    "${SCRIPT_DIR}/generate-icon.sh"
fi

echo "Creating bundle layout..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

echo "Compiling native Swift binary..."
swiftc -O \
    -o "${APP_BUNDLE}/Contents/MacOS/DeepSeekHarnessLauncher" \
    "${SRC_PATH}"

chmod +x "${APP_BUNDLE}/Contents/MacOS/DeepSeekHarnessLauncher"

echo "Copying metadata and assets..."
cp "${PLIST_PATH}" "${APP_BUNDLE}/Contents/Info.plist"
echo -n "APPL????" > "${APP_BUNDLE}/Contents/PkgInfo"
cp "${ICON_PATH}" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
touch "${APP_BUNDLE}"

echo -e "${GREEN}${BOLD}✓ Application successfully built at: ${APP_BUNDLE}${NC}"

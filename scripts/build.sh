#!/usr/bin/env bash
# ==============================================================================
# Build DeepSeek Harness Launcher.app macOS Application Bundle
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DIST_DIR="${REPO_ROOT}/dist"
APP_BUNDLE="${DIST_DIR}/DeepSeek Harness Launcher.app"
ICON_PATH="${REPO_ROOT}/resources/AppIcon.icns"
SRC_PATH="${REPO_ROOT}/src/main.swift"
PLIST_PATH="${REPO_ROOT}/Info.plist"

BOLD='\033[1m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}${BOLD}=== Building DeepSeek Harness Launcher for macOS ===${NC}"

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

BINARY_PATH="${APP_BUNDLE}/Contents/MacOS/DeepSeekHarnessLauncher"
DEPLOYMENT_TARGET="13.0"
TMP_BUILD="$(mktemp -d "${TMPDIR:-/tmp}/dsh-build.XXXXXX")"
trap 'rm -rf "${TMP_BUILD}"' EXIT

# Build one slice per architecture and lipo them together, so a single bundle
# runs natively on both Apple Silicon and Intel.
echo "Compiling native Swift binary (arm64 + x86_64)..."
SLICES=()
for ARCH in arm64 x86_64; do
    SLICE="${TMP_BUILD}/${ARCH}"
    if swiftc -O -target "${ARCH}-apple-macos${DEPLOYMENT_TARGET}" \
        -o "${SLICE}" "${SRC_PATH}" 2>"${TMP_BUILD}/${ARCH}.log"; then
        SLICES+=("${SLICE}")
        echo "  ✓ ${ARCH}"
    else
        echo "  ! ${ARCH} slice failed to build; continuing without it:"
        sed 's/^/    /' "${TMP_BUILD}/${ARCH}.log" | head -n 10
    fi
done

if [ "${#SLICES[@]}" -eq 0 ]; then
    echo -e "${RED}Error: no architecture slice could be built.${NC}"
    exit 1
elif [ "${#SLICES[@]}" -eq 1 ]; then
    echo -e "${RED}Warning: only one architecture built; this bundle is not universal.${NC}"
    cp "${SLICES[0]}" "${BINARY_PATH}"
else
    lipo -create -output "${BINARY_PATH}" "${SLICES[@]}"
fi

chmod +x "${BINARY_PATH}"
echo "Architectures: $(lipo -archs "${BINARY_PATH}")"

echo "Copying metadata and assets..."
cp "${PLIST_PATH}" "${APP_BUNDLE}/Contents/Info.plist"
echo -n "APPL????" > "${APP_BUNDLE}/Contents/PkgInfo"
cp "${ICON_PATH}" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
if [ -f "${REPO_ROOT}/resources/whale-harness.png" ]; then
    cp "${REPO_ROOT}/resources/whale-harness.png" "${APP_BUNDLE}/Contents/Resources/whale-harness.png"
fi

if command -v codesign &>/dev/null; then
    codesign --force --deep --sign - "${APP_BUNDLE}" >/dev/null 2>&1 || true
fi

touch "${APP_BUNDLE}"

echo -e "${GREEN}${BOLD}✓ Application successfully built at: ${APP_BUNDLE}${NC}"

#!/usr/bin/env bash
# ==============================================================================
# Generate AppIcon.icns from resources/favicon.svg using macOS native tools
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
RESOURCES_DIR="${REPO_ROOT}/resources"
SVG_PATH="${RESOURCES_DIR}/favicon.svg"
ICON_PATH="${RESOURCES_DIR}/AppIcon.icns"
TMP_ICONSET="/tmp/dsh_app_icon.iconset"

if [ ! -f "${SVG_PATH}" ]; then
    echo "Error: ${SVG_PATH} not found."
    exit 1
fi

echo "Generating high-resolution macOS icons from SVG..."
mkdir -p "${TMP_ICONSET}"

qlmanage -t -s 1024 -o /tmp "${SVG_PATH}" > /dev/null 2>&1

sips -z 16 16     /tmp/favicon.svg.png --out "${TMP_ICONSET}/icon_16x16.png" > /dev/null
sips -z 32 32     /tmp/favicon.svg.png --out "${TMP_ICONSET}/icon_16x16@2x.png" > /dev/null
sips -z 32 32     /tmp/favicon.svg.png --out "${TMP_ICONSET}/icon_32x32.png" > /dev/null
sips -z 64 64     /tmp/favicon.svg.png --out "${TMP_ICONSET}/icon_32x32@2x.png" > /dev/null
sips -z 128 128   /tmp/favicon.svg.png --out "${TMP_ICONSET}/icon_128x128.png" > /dev/null
sips -z 256 256   /tmp/favicon.svg.png --out "${TMP_ICONSET}/icon_128x128@2x.png" > /dev/null
sips -z 256 256   /tmp/favicon.svg.png --out "${TMP_ICONSET}/icon_256x256.png" > /dev/null
sips -z 512 512   /tmp/favicon.svg.png --out "${TMP_ICONSET}/icon_256x256@2x.png" > /dev/null
sips -z 512 512   /tmp/favicon.svg.png --out "${TMP_ICONSET}/icon_512x512.png" > /dev/null
sips -z 1024 1024 /tmp/favicon.svg.png --out "${TMP_ICONSET}/icon_512x512@2x.png" > /dev/null

iconutil -c icns "${TMP_ICONSET}" -o "${ICON_PATH}"
rm -rf "${TMP_ICONSET}" /tmp/favicon.svg.png

echo "Icon generated successfully: ${ICON_PATH}"

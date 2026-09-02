#!/usr/bin/env bash
# ==============================================================================
# Generate soft-corner AppIcon.icns from resources/whale-harness.png
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
RESOURCES_DIR="${REPO_ROOT}/resources"
SOURCE_PNG="${RESOURCES_DIR}/whale-harness.png"
ICON_PATH="${RESOURCES_DIR}/AppIcon.icns"
TMP_DIR="/tmp/dsh_icon_build_$$"
TMP_1024="${TMP_DIR}/dsh_icon_1024.png"
TMP_ICONSET="${TMP_DIR}/dsh_icon.iconset"

if [ ! -f "${SOURCE_PNG}" ]; then
    if [ -f "${REPO_ROOT}/whale-harness.png" ]; then
        SOURCE_PNG="${REPO_ROOT}/whale-harness.png"
    else
        echo "Error: ${SOURCE_PNG} not found."
        exit 1
    fi
fi

mkdir -p "${TMP_DIR}" "${TMP_ICONSET}"

echo "Rendering 1024x1024 icon preserving transparency and aspect ratio..."
cat << 'SWIFT_EOF' > "${TMP_DIR}/render_icon.swift"
import Cocoa
import CoreGraphics
import Foundation

let args = CommandLine.arguments
guard args.count >= 3 else { exit(1) }
let sourcePath = args[1]
let outputPath = args[2]

guard let sourceImage = NSImage(contentsOfFile: sourcePath) else {
    print("Failed to load \(sourcePath)")
    exit(1)
}

let canvasSize: CGFloat = 1024
let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let context = CGContext(
    data: nil,
    width: Int(canvasSize),
    height: Int(canvasSize),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    print("Failed to create CGContext")
    exit(1)
}

// 1. Transparent background canvas
context.clear(CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize))
context.interpolationQuality = .high

// 2. Draw the source image preserving transparency and aspect ratio without artificial cropping
guard let cgImage = sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    print("Failed to get CGImage")
    exit(1)
}

let imgWidth = CGFloat(cgImage.width)
let imgHeight = CGFloat(cgImage.height)
let scale = min(canvasSize / imgWidth, canvasSize / imgHeight)
let targetWidth = imgWidth * scale
let targetHeight = imgHeight * scale
let originX = (canvasSize - targetWidth) / 2.0
let originY = (canvasSize - targetHeight) / 2.0
let destRect = CGRect(x: originX, y: originY, width: targetWidth, height: targetHeight)

context.draw(cgImage, in: destRect)

guard let outputCGImage = context.makeImage() else {
    print("Failed to make CGImage")
    exit(1)
}

let outputImage = NSImage(cgImage: outputCGImage, size: NSSize(width: canvasSize, height: canvasSize))
guard let tiffData = outputImage.tiffRepresentation,
      let bitmapRep = NSBitmapImageRep(data: tiffData),
      let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
    print("Failed to create PNG data")
    exit(1)
}

try pngData.write(to: URL(fileURLWithPath: outputPath))
SWIFT_EOF

swift "${TMP_DIR}/render_icon.swift" "${SOURCE_PNG}" "${TMP_1024}"

echo "Generating multi-scale iconset for Retina displays..."
sips -z 16 16     "${TMP_1024}" --out "${TMP_ICONSET}/icon_16x16.png" > /dev/null
sips -z 32 32     "${TMP_1024}" --out "${TMP_ICONSET}/icon_16x16@2x.png" > /dev/null
sips -z 32 32     "${TMP_1024}" --out "${TMP_ICONSET}/icon_32x32.png" > /dev/null
sips -z 64 64     "${TMP_1024}" --out "${TMP_ICONSET}/icon_32x32@2x.png" > /dev/null
sips -z 128 128   "${TMP_1024}" --out "${TMP_ICONSET}/icon_128x128.png" > /dev/null
sips -z 256 256   "${TMP_1024}" --out "${TMP_ICONSET}/icon_128x128@2x.png" > /dev/null
sips -z 256 256   "${TMP_1024}" --out "${TMP_ICONSET}/icon_256x256.png" > /dev/null
sips -z 512 512   "${TMP_1024}" --out "${TMP_ICONSET}/icon_256x256@2x.png" > /dev/null
sips -z 512 512   "${TMP_1024}" --out "${TMP_ICONSET}/icon_512x512.png" > /dev/null
sips -z 1024 1024 "${TMP_1024}" --out "${TMP_ICONSET}/icon_512x512@2x.png" > /dev/null

echo "Compiling AppIcon.icns with iconutil..."
iconutil -c icns "${TMP_ICONSET}" -o "${ICON_PATH}"
rm -rf "${TMP_DIR}"

echo "Successfully generated: ${ICON_PATH}"

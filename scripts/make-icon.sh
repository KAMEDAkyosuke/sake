#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Run by hand after changing assets/icon.swift; the .icns it writes is committed, and
# scripts/build-app.sh only copies it. sdk-env.sh is deliberately not sourced: its SDK
# pinning is there for SwiftUI's macros, and this renderer is AppKit and CoreGraphics only.

OUTPUT="${PROJECT_ROOT}/assets/Sake.icns"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

swift "${PROJECT_ROOT}/assets/icon.swift" --iconset "${WORK}/Sake.iconset"
iconutil --convert icns --output "${OUTPUT}" "${WORK}/Sake.iconset"

echo "Created: ${OUTPUT}"

#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

RELEASE=false
OUTPUT_DIR="${PROJECT_ROOT}/target"

usage() {
    echo "Usage: $0 [--release] [--output <dir>]"
    echo ""
    echo "Options:"
    echo "  --release        Build in release mode"
    echo "  --output <dir>   Output directory (default: target/)"
    exit 1
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --release)
            RELEASE=true
            shift
            ;;
        --output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# SwiftUI does not build against the macOS 27.0 SDK with the Command Line Tools alone: that
# SDK declares @State as a macro backed by SwiftUIMacros, and the CLT ship no
# libSwiftUIMacros.dylib. Borrowing Xcode 26.4's plugin does not help either -- its expansion
# wants State._makeStorage_v0, which SDK 27.0's State does not have. A macOS 26 SDK builds
# with nothing but the CLT, so prefer one when the default SDK is 27.x.
#
# `-Xswiftc -sdk` does NOT work here; SwiftPM passes its own -sdk and wins. SDKROOT does.
#
# Delete this block once the CLT ship the plugin, or once an Xcode with the 27 SDK is out.
if [[ -z "${SDKROOT:-}" ]]; then
    default_sdk="$(xcrun --show-sdk-version 2>/dev/null || echo "")"
    if [[ "$default_sdk" == 27.* ]]; then
        fallback="$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX26*.sdk 2>/dev/null \
                    | sort -V | tail -1)"
        if [[ -n "$fallback" ]]; then
            export SDKROOT="$fallback"
            echo "Default SDK is ${default_sdk}; building against $(basename "$SDKROOT") instead"
            echo "  (SDK 27.0 needs libSwiftUIMacros.dylib, which the Command Line Tools omit)"
        else
            echo "WARNING: default SDK is ${default_sdk} and no macOS 26 SDK was found." >&2
            echo "         SwiftUI's @State will fail to expand. Set SDKROOT to a 26.x SDK." >&2
        fi
    fi
fi

if [[ "$RELEASE" == true ]]; then
    CONFIGURATION="release"
else
    CONFIGURATION="debug"
fi

echo "Building sake (${CONFIGURATION})..."
swift build --configuration "${CONFIGURATION}" --package-path "${PROJECT_ROOT}"
BUILD_DIR="$(swift build --configuration "${CONFIGURATION}" --package-path "${PROJECT_ROOT}" --show-bin-path)"

VERSION="$(cat "${PROJECT_ROOT}/VERSION")"
echo "Version: ${VERSION}"

APP_NAME="Sake.app"
APP_DIR="${OUTPUT_DIR}/${APP_NAME}"

echo "Creating ${APP_NAME}..."
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

cp "${BUILD_DIR}/sake" "${APP_DIR}/Contents/MacOS/"

sed "s/VERSION_PLACEHOLDER/${VERSION}/g" "${PROJECT_ROOT}/Info.plist.template" > "${APP_DIR}/Contents/Info.plist"

CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
echo "Signing ${APP_NAME} with identity: ${CODESIGN_IDENTITY}"
codesign --force --deep -s "$CODESIGN_IDENTITY" "${APP_DIR}"

echo "Created: ${APP_DIR}"

if [[ "$RELEASE" == true ]]; then
    ARCH_SUFFIX="-$(uname -m)"
    ZIP_NAME="Sake${ARCH_SUFFIX}-${VERSION}.zip"
    echo "Creating ${ZIP_NAME}..."
    (cd "${OUTPUT_DIR}" && zip -qr "${ZIP_NAME}" "${APP_NAME}")
    echo "Created: ${OUTPUT_DIR}/${ZIP_NAME}"
fi

echo "Done!"

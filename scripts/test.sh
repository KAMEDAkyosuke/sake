#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

source "${SCRIPT_DIR}/sdk-env.sh"

# The tests use swift-testing because the Command Line Tools ship no XCTest module at all:
# `import XCTest` fails with "unable to resolve module dependency".
#
# swift-testing then needs one more push. The CLT *do* ship libTestingMacros.dylib, but in
# usr/lib/swift/host/plugins/testing/ -- a subdirectory SwiftPM does not scan, unlike the
# plugins/ directory above it. Without -plugin-path every @Test fails with "plugin for
# module 'TestingMacros' not found", which reads like the SwiftUI macro problem in
# sdk-env.sh but is a different cause with an actual fix.
#
# Measured 2026-09-19 on CLT 27.0 / Swift 6.4.
PLUGIN_DIR="$(dirname "$(dirname "$(xcrun -f swiftc)")")/lib/swift/host/plugins/testing"
if [[ ! -d "$PLUGIN_DIR" ]]; then
    echo "WARNING: no macro plugin directory at ${PLUGIN_DIR}" >&2
    echo "         swift-testing's @Test will fail to expand; check where the CLT put it." >&2
fi

exec swift test --package-path "${PROJECT_ROOT}" \
    -Xswiftc -plugin-path -Xswiftc "${PLUGIN_DIR}" "$@"

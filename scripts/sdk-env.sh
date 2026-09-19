# Sourced by the other scripts, not run on its own. Chooses the SDK to build against unless
# the caller already set SDKROOT.

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

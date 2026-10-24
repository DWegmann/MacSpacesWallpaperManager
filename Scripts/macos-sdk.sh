#!/bin/bash
set -euo pipefail

# Prefer the macOS 26 SDK when installed, including alongside a newer Xcode.
# The deployment target remains macOS 13; the SDK version is not the minimum runtime version.
if [ -n "${WALLPAPER_MACOS_SDK:-}" ]; then
    APP_SDK_PATH="$WALLPAPER_MACOS_SDK"
else
    SELECTED_SDK="$(/usr/bin/xcrun --sdk macosx --show-sdk-path)"
    if [ -d "$(dirname "$SELECTED_SDK")/MacOSX26.sdk" ]; then
        APP_SDK_PATH="$(dirname "$SELECTED_SDK")/MacOSX26.sdk"
    elif [ -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk ]; then
        APP_SDK_PATH=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk
    else
        APP_SDK_PATH="$SELECTED_SDK"
    fi
fi

if [ ! -f "$APP_SDK_PATH/SDKSettings.plist" ]; then
    printf 'Kein gültiges macOS-SDK: %s\n' "$APP_SDK_PATH" >&2
    exit 1
fi
SDK_NAME="$(/usr/bin/plutil -extract CanonicalName raw "$APP_SDK_PATH/SDKSettings.plist")"
case "$SDK_NAME" in
    macosx*) ;;
    *) printf 'Es wird ein macOS-SDK benötigt: %s\n' "$SDK_NAME" >&2; exit 1 ;;
esac
cd "$APP_SDK_PATH"
pwd -P

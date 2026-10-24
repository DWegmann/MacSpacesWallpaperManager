#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_ACTION="${1:-build}"
BUILD_ROOT="${WALLPAPER_BUILD_ROOT:-${SPACEPAPER_BUILD_ROOT:-$PROJECT_ROOT/.build}}"
if [ "$#" -gt 0 ]; then shift; fi
cd "$PROJECT_ROOT"

# Prefer full Xcode when installed: it also supplies XCTest and both architectures' compatibility libraries.
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

APP_SDK_PATH="$("$PROJECT_ROOT/Scripts/macos-sdk.sh")"
# SwiftPM passes --sysroot to clang when linking. On Darwin, an inherited SDKROOT can otherwise
# select a different SDK for the linker despite Swift's explicit -sdk argument.
export SDKROOT="$APP_SDK_PATH"

# Keep every compiler/manifest cache inside the project, including in restricted workspaces.
export CLANG_MODULE_CACHE_PATH="$BUILD_ROOT/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$BUILD_ROOT/manifest-module-cache"

exec /usr/bin/xcrun swift "$BUILD_ACTION" \
    --sdk "$APP_SDK_PATH" \
    --build-system native \
    --disable-sandbox \
    --cache-path "$BUILD_ROOT/cache" \
    --config-path "$BUILD_ROOT/config" \
    --security-path "$BUILD_ROOT/security" \
    --scratch-path "$BUILD_ROOT/spm" \
    -Xswiftc -module-cache-path -Xswiftc "$BUILD_ROOT/module-cache" \
    "$@"

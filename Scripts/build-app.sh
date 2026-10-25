#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"
APP_BUNDLE="$PROJECT_ROOT/dist/Mac Spaces Wallpaper Manager.app"
APP_EXECUTABLE="MacSpacesWallpaperManager"
SIGN_IDENTITY="${SIGNING_IDENTITY:--}"
BUILD_ROOT="${WALLPAPER_BUILD_ROOT:-${SPACEPAPER_BUILD_ROOT:-$PROJECT_ROOT/.build}}"
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

export WALLPAPER_MACOS_SDK="$("$PROJECT_ROOT/Scripts/macos-sdk.sh")"
export SDKROOT="$WALLPAPER_MACOS_SDK"
APP_SDK_NAME="$(/usr/bin/plutil -extract CanonicalName raw "$WALLPAPER_MACOS_SDK/SDKSettings.plist")"
APP_SDK_VERSION="$(/usr/bin/plutil -extract Version raw "$WALLPAPER_MACOS_SDK/SDKSettings.plist")"
printf 'Build-SDK: %s · Mindestversion: macOS 13 · Ziel: einschließlich macOS 26\n' "$APP_SDK_NAME"

for architecture in arm64 x86_64; do
    "$PROJECT_ROOT/Scripts/swift-task.sh" build -c release --triple "$architecture-apple-macosx13.0"
done

ARM_BIN_DIR="$("$PROJECT_ROOT/Scripts/swift-task.sh" build -c release --triple arm64-apple-macosx13.0 --show-bin-path)"
INTEL_BIN_DIR="$("$PROJECT_ROOT/Scripts/swift-task.sh" build -c release --triple x86_64-apple-macosx13.0 --show-bin-path)"
SPARKLE_ARTIFACT="$BUILD_ROOT/spm/artifacts/sparkle/Sparkle"
SPARKLE_FRAMEWORK="$SPARKLE_ARTIFACT/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [ ! -d "$SPARKLE_FRAMEWORK" ]; then
    printf 'Sparkle.framework fehlt: %s\n' "$SPARKLE_FRAMEWORK" >&2
    exit 1
fi
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources" "$APP_BUNDLE/Contents/Frameworks"
# Replace the previous copy so stale framework files cannot survive a rebuild.
rm -rf "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
/usr/bin/ditto "$SPARKLE_FRAMEWORK" "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
# The app is not sandboxed. Sparkle's optional sandbox XPC services are not needed.
rm -rf "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices"
cp "$PROJECT_ROOT/ThirdPartyNotices.md" "$APP_BUNDLE/Contents/Resources/ThirdPartyNotices.md"
cp "$PROJECT_ROOT/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
/usr/bin/plutil -insert DTSDKName -string "$APP_SDK_NAME" "$APP_BUNDLE/Contents/Info.plist"
/usr/bin/xcrun lipo -create "$ARM_BIN_DIR/$APP_EXECUTABLE" "$INTEL_BIN_DIR/$APP_EXECUTABLE" \
    -output "$APP_BUNDLE/Contents/MacOS/$APP_EXECUTABLE"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_EXECUTABLE"

/usr/bin/xcrun swift -sdk "$WALLPAPER_MACOS_SDK" -target "$(uname -m)-apple-macosx13.0" \
    -module-cache-path "$BUILD_ROOT/module-cache" \
    "$PROJECT_ROOT/Tools/GenerateIcon.swift" "$BUILD_ROOT/AppIcon.iconset" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

sign_code() {
    if [ "$SIGN_IDENTITY" = "-" ]; then
        /usr/bin/codesign --force --sign - "$1"
    else
        /usr/bin/codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$1"
    fi
}
# Sign inside out. Do not use --deep for signing nested executable code.
EMBEDDED_SPARKLE="$APP_BUNDLE/Contents/Frameworks/Sparkle.framework/Versions/B"
sign_code "$EMBEDDED_SPARKLE/Autoupdate"
sign_code "$EMBEDDED_SPARKLE/Updater.app"
sign_code "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
sign_code "$APP_BUNDLE"
/usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"
APP_ARCHITECTURES="$(/usr/bin/xcrun lipo -archs "$APP_BUNDLE/Contents/MacOS/$APP_EXECUTABLE")"
case "$APP_ARCHITECTURES" in
    "arm64 x86_64"|"x86_64 arm64") ;;
    *) printf 'Unerwartete Architekturen: %s\n' "$APP_ARCHITECTURES" >&2; exit 1 ;;
esac
SDK_STAMPS="$(/usr/bin/xcrun vtool -show-build "$APP_BUNDLE/Contents/MacOS/$APP_EXECUTABLE" | /usr/bin/awk '$1 == "sdk" { print $2 }')"
if [ -z "$SDK_STAMPS" ]; then
    printf 'Die SDK-Angabe im Universal-Binary konnte nicht geprüft werden.\n' >&2
    exit 1
fi
while IFS= read -r SDK_STAMP; do
    if [ "$SDK_STAMP" != "$APP_SDK_VERSION" ]; then
        printf 'SDK-Abweichung im Binary: %s statt %s. Bitte den Build-Cache leeren und erneut bauen.\n' "$SDK_STAMP" "$APP_SDK_VERSION" >&2
        exit 1
    fi
done <<< "$SDK_STAMPS"
/usr/bin/plutil -lint "$APP_BUNDLE/Contents/Info.plist"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$PROJECT_ROOT/dist/Mac-Spaces-Wallpaper-Manager-universal.zip"
printf '\nFertig: %s\nUniversal: arm64 + x86_64, ab macOS 13\n' "$APP_BUNDLE"

if [ "${1:-}" = "--open" ]; then /usr/bin/open "$APP_BUNDLE"; fi

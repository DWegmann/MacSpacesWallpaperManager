#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_BUNDLE="$PROJECT_ROOT/dist/Mac Spaces Wallpaper Manager.app"
SPARKLE_TOOL="$PROJECT_ROOT/Scripts/sparkle-tool.sh"
KEY_ACCOUNT="app.spacepaper.mac"
REPOSITORY_URL="https://github.com/DWegmann/MacSpacesWallpaperManager"
ARCHIVE_NAME="Mac-Spaces-Wallpaper-Manager-universal.zip"

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ] || [ ! -f "$APP_BUNDLE/Contents/Info.plist" ]; then
    printf 'Verwendung: %s RELEASE-TAG [RELEASE-NOTES.md]\nZuerst ./Scripts/build-app.sh ausführen.\n' "$0" >&2
    exit 1
fi
VERSION="$(/usr/bin/plutil -extract CFBundleShortVersionString raw "$APP_BUNDLE/Contents/Info.plist")"
if [ "$1" != "v$VERSION" ]; then
    printf 'Release-Tag muss zur gebauten App passen: v%s\n' "$VERSION" >&2
    exit 1
fi
RELEASE_TAG="$1"
NOTES_FILE="${2:-$PROJECT_ROOT/ReleaseNotes/$RELEASE_TAG.md}"
if [ ! -s "$NOTES_FILE" ]; then
    printf 'Release Notes fehlen: %s\n' "$NOTES_FILE" >&2
    exit 1
fi

# Require the original signing key; never generate or replace release keys implicitly.
APP_PUBLIC_KEY="$(/usr/bin/plutil -extract SUPublicEDKey raw "$APP_BUNDLE/Contents/Info.plist")"
SIGNING_PUBLIC_KEY="$("$SPARKLE_TOOL" generate_keys --account "$KEY_ACCOUNT" -p)"
if [ "$APP_PUBLIC_KEY" != "$SIGNING_PUBLIC_KEY" ]; then
    printf 'Der Schlüsselbund-Schlüssel passt nicht zum öffentlichen Schlüssel der App. Release abgebrochen.\n' >&2
    exit 1
fi
/usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"

RELEASE_DIR="$PROJECT_ROOT/dist/updates/$RELEASE_TAG"
if [ -e "$RELEASE_DIR" ]; then
    printf 'Release-Ordner existiert bereits: %s\nBitte zuerst sichern oder entfernen.\n' "$RELEASE_DIR" >&2
    exit 1
fi
mkdir -p "$RELEASE_DIR"
# Package the final app again, including a stapled notarization ticket if present.
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$RELEASE_DIR/$ARCHIVE_NAME"
cp "$NOTES_FILE" "$RELEASE_DIR/${ARCHIVE_NAME%.zip}.md"
"$SPARKLE_TOOL" generate_appcast --account "$KEY_ACCOUNT" \
    --download-url-prefix "$REPOSITORY_URL/releases/download/$RELEASE_TAG/" \
    --link "$REPOSITORY_URL/releases/tag/$RELEASE_TAG" \
    --embed-release-notes --maximum-deltas 0 --maximum-versions 1 \
    -o "$RELEASE_DIR/appcast.xml" "$RELEASE_DIR"

# Fail closed: validate both the signed feed and the exact archive it advertises.
"$SPARKLE_TOOL" sign_update --account "$KEY_ACCOUNT" --verify "$RELEASE_DIR/appcast.xml"
ARCHIVE_SIGNATURE="$(/usr/bin/xmllint --xpath "string(//*[local-name()='enclosure']/@*[local-name()='edSignature'])" "$RELEASE_DIR/appcast.xml")"
ARCHIVE_LENGTH="$(/usr/bin/xmllint --xpath "string(//*[local-name()='enclosure']/@length)" "$RELEASE_DIR/appcast.xml")"
ARCHIVE_URL="$(/usr/bin/xmllint --xpath "string(//*[local-name()='enclosure']/@url)" "$RELEASE_DIR/appcast.xml")"
if [ "$ARCHIVE_LENGTH" != "$(/usr/bin/stat -f %z "$RELEASE_DIR/$ARCHIVE_NAME")" ] || \
   [ "$ARCHIVE_URL" != "$REPOSITORY_URL/releases/download/$RELEASE_TAG/$ARCHIVE_NAME" ]; then
    printf 'Appcast enthält eine unerwartete Download-URL oder Dateigröße.\n' >&2
    exit 1
fi
"$SPARKLE_TOOL" sign_update --account "$KEY_ACCOUNT" --verify "$RELEASE_DIR/$ARCHIVE_NAME" "$ARCHIVE_SIGNATURE"
printf '\nGeprüfte Release-Dateien:\n%s\n%s\n\nBeide Dateien gemeinsam als Assets von %s veröffentlichen und das Release als latest markieren.\nEs wurde nichts hochgeladen.\n' \
    "$RELEASE_DIR/$ARCHIVE_NAME" "$RELEASE_DIR/appcast.xml" "$RELEASE_TAG"

#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_ROOT="${WALLPAPER_BUILD_ROOT:-${SPACEPAPER_BUILD_ROOT:-$PROJECT_ROOT/.build}}"
SPARKLE_BIN="$BUILD_ROOT/spm/artifacts/sparkle/Sparkle/bin"
case "${1:-}" in
    generate_keys|generate_appcast|sign_update) SPARKLE_TOOL="$1"; shift ;;
    *) printf 'Verwendung: %s {generate_keys|generate_appcast|sign_update} [Argumente …]\n' "$0" >&2; exit 1 ;;
esac
if [ ! -x "$SPARKLE_BIN/$SPARKLE_TOOL" ]; then
    printf 'Sparkle-Werkzeuge fehlen. Zuerst ./Scripts/build-app.sh ausführen (mit demselben WALLPAPER_BUILD_ROOT).\n' >&2
    exit 1
fi
exec "$SPARKLE_BIN/$SPARKLE_TOOL" "$@"

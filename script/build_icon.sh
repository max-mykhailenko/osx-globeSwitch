#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$ROOT_DIR/Resources/IconDesign/Fold-original.png"
ICON_TEMP="$(mktemp -d "${TMPDIR:-/tmp}/GlobeSwitchIcon.XXXXXX")"
trap 'rm -rf "$ICON_TEMP"' EXIT
ICONSET="$ICON_TEMP/AppIcon.iconset"
mkdir -p "$ICONSET"

# Package the selected design into every standard macOS ICNS representation.
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$SOURCE" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  retina=$((size * 2))
  sips -z "$retina" "$retina" "$SOURCE" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
cp "$ICONSET/icon_512x512@2x.png" "$ROOT_DIR/Resources/AppIcon-1024.png"
iconutil -c icns "$ICONSET" -o "$ROOT_DIR/Resources/AppIcon.icns"
echo "Built Resources/AppIcon.icns from the selected Fold design."

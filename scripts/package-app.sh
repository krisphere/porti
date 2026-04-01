#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="${PORTI_APP_NAME:-Porti}"
EXECUTABLE_NAME="PortiApp"
BUNDLE_IDENTIFIER="${PORTI_BUNDLE_IDENTIFIER:-io.github.krisphere.porti}"
VERSION="${PORTI_VERSION:-0.1.1}"
BUILD_NUMBER="${PORTI_BUILD:-1}"
APPCAST_URL="${PORTI_APPCAST_URL:-https://github.com/krisphere/porti/releases/latest/download/appcast.xml}"
SPARKLE_PUBLIC_KEY="${PORTI_SPARKLE_PUBLIC_KEY:-}"
APP_ICON_SOURCE="${PORTI_APP_ICON_SOURCE:-$ROOT_DIR/packaging/AppIconSource/porti.png}"
CONFIGURATION="${CONFIGURATION:-release}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/dist}"
BIN_DIR=""
APP_BUNDLE=""
ZIP_PATH=""

render_icon() {
  local source_png="$1"
  local output_icns="$2"
  local iconset_dir

  if [[ ! -f "$source_png" ]]; then
    echo "icon source not found: $source_png" >&2
    exit 1
  fi

  iconset_dir="$(mktemp -d "${TMPDIR:-/tmp}/porti-iconset.XXXXXX").iconset"
  mv "${iconset_dir%.iconset}" "$iconset_dir"

  sips -z 16 16 "$source_png" --out "$iconset_dir/icon_16x16.png" >/dev/null
  sips -z 32 32 "$source_png" --out "$iconset_dir/icon_16x16@2x.png" >/dev/null
  sips -z 32 32 "$source_png" --out "$iconset_dir/icon_32x32.png" >/dev/null
  sips -z 64 64 "$source_png" --out "$iconset_dir/icon_32x32@2x.png" >/dev/null
  sips -z 128 128 "$source_png" --out "$iconset_dir/icon_128x128.png" >/dev/null
  sips -z 256 256 "$source_png" --out "$iconset_dir/icon_128x128@2x.png" >/dev/null
  sips -z 256 256 "$source_png" --out "$iconset_dir/icon_256x256.png" >/dev/null
  sips -z 512 512 "$source_png" --out "$iconset_dir/icon_256x256@2x.png" >/dev/null
  sips -z 512 512 "$source_png" --out "$iconset_dir/icon_512x512.png" >/dev/null
  cp "$source_png" "$iconset_dir/icon_512x512@2x.png"

  iconutil -c icns "$iconset_dir" -o "$output_icns"
  rm -rf "$iconset_dir"
}

if [[ -z "$SPARKLE_PUBLIC_KEY" ]]; then
  echo "PORTI_SPARKLE_PUBLIC_KEY must be set to your Sparkle SUPublicEDKey" >&2
  exit 1
fi

cd "$ROOT_DIR"

swift build -c "$CONFIGURATION"
BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"

EXECUTABLE_PATH="$BIN_DIR/$EXECUTABLE_NAME"
SPARKLE_FRAMEWORK_PATH="$BIN_DIR/Sparkle.framework"
INFO_TEMPLATE="$ROOT_DIR/packaging/Porti-Info.plist.template"

if [[ ! -x "$EXECUTABLE_PATH" ]]; then
  echo "executable not found: $EXECUTABLE_PATH" >&2
  exit 1
fi

if [[ ! -d "$SPARKLE_FRAMEWORK_PATH" ]]; then
  echo "Sparkle framework not found: $SPARKLE_FRAMEWORK_PATH" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
APP_BUNDLE="$OUTPUT_DIR/$APP_NAME.app"
ZIP_PATH="$OUTPUT_DIR/$APP_NAME-$VERSION.zip"

rm -rf "$APP_BUNDLE" "$ZIP_PATH"
mkdir -p \
  "$APP_BUNDLE/Contents/MacOS" \
  "$APP_BUNDLE/Contents/Frameworks" \
  "$APP_BUNDLE/Contents/Resources"

cp "$EXECUTABLE_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp -R "$SPARKLE_FRAMEWORK_PATH" "$APP_BUNDLE/Contents/Frameworks/"
render_icon "$APP_ICON_SOURCE" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

if command -v install_name_tool >/dev/null 2>&1; then
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_BUNDLE/Contents/MacOS/$APP_NAME" 2>/dev/null || true
fi

sed \
  -e "s|__APP_NAME__|$APP_NAME|g" \
  -e "s|__EXECUTABLE_NAME__|$APP_NAME|g" \
  -e "s|__BUNDLE_IDENTIFIER__|$BUNDLE_IDENTIFIER|g" \
  -e "s|__VERSION__|$VERSION|g" \
  -e "s|__BUILD__|$BUILD_NUMBER|g" \
  -e "s|__APPCAST_URL__|$APPCAST_URL|g" \
  -e "s|__SPARKLE_PUBLIC_KEY__|$SPARKLE_PUBLIC_KEY|g" \
  "$INFO_TEMPLATE" > "$APP_BUNDLE/Contents/Info.plist"

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null
fi

ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"

echo "Created app bundle: $APP_BUNDLE"
echo "Created zip archive: $ZIP_PATH"

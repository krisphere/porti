#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="${PORTI_APP_NAME:-Porti}"
EXECUTABLE_NAME="PortiApp"
BUNDLE_IDENTIFIER="${PORTI_BUNDLE_IDENTIFIER:-io.github.krisphere.porti}"
VERSION="${PORTI_VERSION:-0.1.0}"
BUILD_NUMBER="${PORTI_BUILD:-1}"
APPCAST_URL="${PORTI_APPCAST_URL:-https://github.com/krisphere/porti/releases/latest/download/appcast.xml}"
SPARKLE_PUBLIC_KEY="${PORTI_SPARKLE_PUBLIC_KEY:-}"
CONFIGURATION="${CONFIGURATION:-release}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/dist}"
BIN_DIR=""
APP_BUNDLE=""
ZIP_PATH=""

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

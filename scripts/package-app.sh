#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="${PORTI_APP_NAME:-Porti}"
EXECUTABLE_NAME="PortiApp"
BUNDLE_IDENTIFIER="${PORTI_BUNDLE_IDENTIFIER:-io.github.kysz.porti}"
VERSION="${PORTI_VERSION:-0.1.13}"
APPCAST_URL="${PORTI_APPCAST_URL:-https://github.com/kysz/porti/releases/latest/download/appcast.xml}"
SPARKLE_PUBLIC_KEY="${PORTI_SPARKLE_PUBLIC_KEY:-1lnMBb7o0WzU8i/RDS+2oLm4G2m3FfCDvy6GpC4Duo0=}"
APP_ICON_SOURCE="${PORTI_APP_ICON_SOURCE:-$ROOT_DIR/packaging/AppIconSource/porti.png}"
CONFIGURATION="${CONFIGURATION:-release}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/dist}"
XCODE_BUILD_DIR="${XCODE_BUILD_DIR:-$ROOT_DIR/.build/xcode-package}"
XCODE_CONFIGURATION=""
XCODE_PRODUCTS_DIR=""
XCODE_INTERMEDIATES_DIR=""
EXECUTABLE_PATH=""
SPARKLE_FRAMEWORK_PATH=""
APP_BUNDLE=""
ZIP_PATH=""

version_to_build_number() {
  local version="$1"
  local major=0
  local minor=0
  local patch=0

  IFS='.' read -r major minor patch <<< "$version"
  major="${major:-0}"
  minor="${minor:-0}"
  patch="${patch:-0}"

  printf '%d%03d%03d\n' "$major" "$minor" "$patch"
}

BUILD_NUMBER="${PORTI_BUILD:-$(version_to_build_number "$VERSION")}"

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

build_with_xcode() {
  local configuration_name="$1"
  local derived_data_path="$2"

  rm -rf "$derived_data_path"

  xcodebuild \
    -scheme "$EXECUTABLE_NAME" \
    -destination "platform=macOS" \
    -configuration "$configuration_name" \
    -derivedDataPath "$derived_data_path" \
    build
}

generate_app_intents_metadata() {
  local derived_data_path="$1"
  local configuration_name="$2"
  local output_parent="$3"
  local sdk_root
  local objects_dir
  local arch
  local target_triple
  local dependency_file
  local source_file_list
  local metadata_file_list
  local static_metadata_file_list
  local stringsdata_file
  local swift_const_values_list
  local xcode_build_version

  sdk_root="$(xcrun --sdk macosx --show-sdk-path)"
  objects_dir="$derived_data_path/Build/Intermediates.noindex/Porti.build/$configuration_name/$EXECUTABLE_NAME.build/Objects-normal"

  arch="$(find "$objects_dir" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | head -n 1)"
  if [[ -z "$arch" ]]; then
    echo "could not determine build architecture for App Intents metadata" >&2
    exit 1
  fi

  target_triple="$arch-apple-macos13.0"
  dependency_file="$objects_dir/$arch/$EXECUTABLE_NAME"_dependency_info.dat
  source_file_list="$objects_dir/$arch/$EXECUTABLE_NAME.SwiftFileList"
  metadata_file_list="$derived_data_path/Build/Intermediates.noindex/Porti.build/$configuration_name/$EXECUTABLE_NAME.build/$EXECUTABLE_NAME.DependencyMetadataFileList"
  static_metadata_file_list="$derived_data_path/Build/Intermediates.noindex/Porti.build/$configuration_name/$EXECUTABLE_NAME.build/$EXECUTABLE_NAME.DependencyStaticMetadataFileList"
  stringsdata_file="$objects_dir/$arch/ExtractedAppShortcutsMetadata.stringsdata"
  swift_const_values_list="$derived_data_path/Build/Intermediates.noindex/Porti.build/$configuration_name/$EXECUTABLE_NAME.build/Objects-normal/$arch/$EXECUTABLE_NAME.SwiftConstValuesFileList"
  xcode_build_version="$(xcodebuild -version | awk 'NR==2 { print $3 }')"

  find "$objects_dir/$arch" -name '*.swiftconstvalues' | sort > "$swift_const_values_list"

  xcrun appintentsmetadataprocessor \
    --toolchain-dir /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain \
    --module-name "$EXECUTABLE_NAME" \
    --sdk-root "$sdk_root" \
    --xcode-version "$xcode_build_version" \
    --platform-family macOS \
    --deployment-target 13.0 \
    --bundle-identifier "$BUNDLE_IDENTIFIER" \
    --output "$output_parent" \
    --target-triple "$target_triple" \
    --binary-file "$EXECUTABLE_PATH" \
    --dependency-file "$dependency_file" \
    --stringsdata-file "$stringsdata_file" \
    --source-file-list "$source_file_list" \
    --metadata-file-list "$metadata_file_list" \
    --static-metadata-file-list "$static_metadata_file_list" \
    --swift-const-vals-list "$swift_const_values_list" \
    --force \
    --compile-time-extraction \
    --deployment-aware-processing \
    --validate-assistant-intents \
    --no-app-shortcuts-localization
}

cd "$ROOT_DIR"

XCODE_CONFIGURATION="$(tr '[:lower:]' '[:upper:]' <<< "${CONFIGURATION:0:1}")${CONFIGURATION:1}"
build_with_xcode "$XCODE_CONFIGURATION" "$XCODE_BUILD_DIR"
XCODE_PRODUCTS_DIR="$XCODE_BUILD_DIR/Build/Products/$XCODE_CONFIGURATION"
XCODE_INTERMEDIATES_DIR="$XCODE_BUILD_DIR/Build/Intermediates.noindex"

EXECUTABLE_PATH="$XCODE_PRODUCTS_DIR/$EXECUTABLE_NAME"
SPARKLE_FRAMEWORK_PATH="$XCODE_PRODUCTS_DIR/PackageFrameworks/Sparkle.framework"
if [[ ! -d "$SPARKLE_FRAMEWORK_PATH" ]]; then
  SPARKLE_FRAMEWORK_PATH="$XCODE_PRODUCTS_DIR/Sparkle.framework"
fi
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

shopt -s nullglob
for resource_bundle in "$XCODE_PRODUCTS_DIR"/*.bundle; do
  cp -R "$resource_bundle" "$APP_BUNDLE/Contents/Resources/"
done
shopt -u nullglob

generate_app_intents_metadata "$XCODE_BUILD_DIR" "$XCODE_CONFIGURATION" "$APP_BUNDLE/Contents/Resources"

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

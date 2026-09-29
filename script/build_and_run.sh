#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="MelonGallery"
BUNDLE_NAME="Melon Gallery"
BUNDLE_ID="dev.neolin.MelonGallery"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
SWIFTPM_CACHE_DIR="$ROOT_DIR/.build/swiftpm-cache"
SWIFTPM_CONFIG_DIR="$ROOT_DIR/.build/swiftpm-config"
SWIFTPM_SECURITY_DIR="$ROOT_DIR/.build/swiftpm-security"
CLANG_CACHE_DIR="${CLANG_MODULE_CACHE_PATH:-$ROOT_DIR/.build/clang-module-cache}"
APP_BUNDLE="$DIST_DIR/$BUNDLE_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_HELPERS="$APP_CONTENTS/Helpers"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
APP_ICON_SOURCE="$ROOT_DIR/Sources/MelonGallery/Resources/AppIcon.icns"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

mkdir -p "$SWIFTPM_CACHE_DIR" "$SWIFTPM_CONFIG_DIR" "$SWIFTPM_SECURITY_DIR" "$CLANG_CACHE_DIR"

SWIFT_BUILD_FLAGS=(
  --disable-sandbox
  --cache-path "$SWIFTPM_CACHE_DIR"
  --config-path "$SWIFTPM_CONFIG_DIR"
  --security-path "$SWIFTPM_SECURITY_DIR"
  --scratch-path "$ROOT_DIR/.build"
)

CLANG_MODULE_CACHE_PATH="$CLANG_CACHE_DIR" swift build "${SWIFT_BUILD_FLAGS[@]}"
BUILD_DIR="$(CLANG_MODULE_CACHE_PATH="$CLANG_CACHE_DIR" swift build "${SWIFT_BUILD_FLAGS[@]}" --show-bin-path)"
BUILD_BINARY="$BUILD_DIR/$APP_NAME"
RESOURCE_BUNDLE="$BUILD_DIR/MelonGallery_MelonGallery.bundle"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES" "$APP_HELPERS"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
cp "$BUILD_DIR/MelonRAWDecoder" "$APP_HELPERS/MelonRAWDecoder"
chmod +x "$APP_HELPERS/MelonRAWDecoder"
cp "$APP_ICON_SOURCE" "$APP_RESOURCES/AppIcon.icns"

if [[ -d "$RESOURCE_BUNDLE" ]]; then
  cp -R "$RESOURCE_BUNDLE" "$APP_BUNDLE/"
fi

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$BUNDLE_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon.icns</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.graphics-design</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  build)
    echo "Built $APP_BUNDLE"
    ;;
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [build|run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac

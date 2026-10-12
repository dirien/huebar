#!/usr/bin/env bash
# Builds build/HueBar.app.
#   ./build.sh            build only
#   ./build.sh --install  build, copy to /Applications and launch
#
# Environment:
#   VERSION=1.2.3      marketing version written to Info.plist (default 0.0.0)
#   BUILD_NUMBER=42    CFBundleVersion (default 1)
#   UNIVERSAL=1        build for both arm64 and x86_64 (needs Xcode, not just the Command Line Tools)
#   SIGN_IDENTITY=...  sign with this identity, e.g. "Developer ID Application: Jane Doe (TEAMID)".
#                      Defaults to an ad-hoc signature.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME=HueBar
APP="build/$APP_NAME.app"
VERSION="${VERSION:-0.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

BUILD_FLAGS=(-c release)
if [[ "${UNIVERSAL:-0}" == 1 ]]; then
  BUILD_FLAGS+=(--arch arm64 --arch x86_64)
fi

swift build "${BUILD_FLAGS[@]}"
BIN_DIR="$(swift build "${BUILD_FLAGS[@]}" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# CFBundleShortVersionString must be numeric, so drop any pre-release suffix ("1.2.0-beta.1" -> "1.2.0").
plutil -replace CFBundleShortVersionString -string "${VERSION%%-*}" "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$APP/Contents/Info.plist"

if [[ "$SIGN_IDENTITY" == "-" ]]; then
  # Ad hoc: required to run on Apple silicon and for the Local Network permission prompt.
  codesign --force --sign - --timestamp=none "$APP"
else
  # Hardened runtime and a secure timestamp are required for notarization.
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
fi
codesign --verify --strict "$APP"
echo "Built $APP $VERSION ($(lipo -archs "$APP/Contents/MacOS/$APP_NAME"))"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x "$APP_NAME" 2>/dev/null || true
  rm -rf "/Applications/$APP_NAME.app"
  cp -R "$APP" /Applications/
  open "/Applications/$APP_NAME.app"
  echo "Installed /Applications/$APP_NAME.app"
fi

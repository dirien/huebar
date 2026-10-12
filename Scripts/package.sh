#!/usr/bin/env bash
# Packages build/HueBar.app (from build.sh) for download:
#   build/HueBar-$VERSION.dmg   drag-to-Applications disk image
#   build/HueBar-$VERSION.zip   plain archive (what Homebrew casks and updaters usually want)
#   build/SHA256SUMS.txt
#
# Environment:
#   VERSION=1.2.3                required
#   SIGN_IDENTITY=...            Developer ID identity; signs the DMG too (default: leave unsigned)
#   NOTARY_APPLE_ID, NOTARY_TEAM_ID, NOTARY_PASSWORD
#                                when all three are set, notarize with Apple and staple the tickets.
#                                NOTARY_PASSWORD is an app-specific password from account.apple.com.
set -euo pipefail
cd "$(dirname "$0")/.."

: "${VERSION:?Set VERSION, e.g. VERSION=1.2.3}"
APP_NAME=HueBar
APP="build/$APP_NAME.app"
DMG="build/$APP_NAME-$VERSION.dmg"
ZIP="build/$APP_NAME-$VERSION.zip"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

[[ -d "$APP" ]] || { echo "$APP not found; run build.sh first" >&2; exit 1; }

staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
cp -R "$APP" "$staging/"
ln -s /Applications "$staging/Applications"
rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$staging" -fs HFS+ -format UDZO -imagekey zlib-level=9 "$DMG"

if [[ "$SIGN_IDENTITY" != "-" ]]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
fi

if [[ -n "${NOTARY_APPLE_ID:-}" && -n "${NOTARY_TEAM_ID:-}" && -n "${NOTARY_PASSWORD:-}" ]]; then
  # Notarizing the DMG also covers the app inside it, so both can be stapled afterwards.
  xcrun notarytool submit "$DMG" --wait \
    --apple-id "$NOTARY_APPLE_ID" --team-id "$NOTARY_TEAM_ID" --password "$NOTARY_PASSWORD"
  xcrun stapler staple "$DMG"
  xcrun stapler staple "$APP"
  spctl --assess --type open --context context:primary-signature --verbose "$DMG"
else
  echo "Notarization skipped (NOTARY_APPLE_ID, NOTARY_TEAM_ID and NOTARY_PASSWORD not all set)."
fi

rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

(cd build && shasum -a 256 "$(basename "$DMG")" "$(basename "$ZIP")" > SHA256SUMS.txt)
echo "Packaged:"
cat build/SHA256SUMS.txt

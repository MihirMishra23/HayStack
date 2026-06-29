#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCHEME="HayStack"
CONFIGURATION="${1:-Release}"
ARCHIVE_PATH="$ROOT_DIR/build/HayStack.xcarchive"
APP_PATH="$ARCHIVE_PATH/Products/Applications/HayStack.app"
DMG_PATH="$ROOT_DIR/build/HayStack.dmg"
STAGING_DIR="$ROOT_DIR/build/dmg-staging"

cd "$ROOT_DIR"

echo "==> Resolving Swift packages"
xcodebuild -resolvePackageDependencies -project HayStack.xcodeproj -scheme "$SCHEME"

echo "==> Archiving ($CONFIGURATION)"
xcodebuild \
  -project HayStack.xcodeproj \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -archivePath "$ARCHIVE_PATH" \
  archive \
  CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}" \
  DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-}"

if [[ "${SKIP_NOTARIZE:-0}" == "1" ]]; then
  echo "==> Skipping notarization (SKIP_NOTARIZE=1)"
else
  if [[ -z "${DEVELOPER_ID:-}" ]]; then
    echo "Set DEVELOPER_ID to your Developer ID Application identity to notarize."
    echo "Example: DEVELOPER_ID='Developer ID Application: Your Name (TEAMID)'"
    exit 1
  fi

  echo "==> Signing app"
  codesign --force --deep --options runtime --sign "$DEVELOPER_ID" "$APP_PATH"

  echo "==> Creating zip for notarization"
  ZIP_PATH="$ROOT_DIR/build/HayStack.zip"
  ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

  echo "==> Submitting for notarization"
  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_ID_PASSWORD:-}" && -n "${APPLE_TEAM_ID:-}" ]]; then
    xcrun notarytool submit "$ZIP_PATH" \
      --apple-id "$APPLE_ID" \
      --password "$APPLE_ID_PASSWORD" \
      --team-id "$APPLE_TEAM_ID" \
      --wait
  else
    echo "Provide NOTARY_PROFILE or APPLE_ID/APPLE_ID_PASSWORD/APPLE_TEAM_ID for notarization."
    exit 1
  fi

  echo "==> Stapling notarization ticket"
  xcrun stapler staple "$APP_PATH"
fi

echo "==> Creating DMG"
rm -rf "$STAGING_DIR" "$DMG_PATH"
mkdir -p "$STAGING_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
  -volname "HayStack" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "==> Done"
echo "Archive: $ARCHIVE_PATH"
echo "DMG: $DMG_PATH"

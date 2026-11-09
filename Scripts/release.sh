#!/bin/zsh
# Release build: Developer ID signing, notarization, DMG.
#
#   Scripts/release.sh <version> <build>     e.g. Scripts/release.sh 1.0 1
#
# Produces in build/release/:
#   CaptionOverlay-<version>.dmg     notarized and stapled: the download for GitHub Releases
#   CaptionOverlay-<version>.zip     the notarized app as a zip
#
# One-time prerequisites:
#   - Xcode > Settings > Accounts > Manage Certificates > "+" > Developer ID Application
#   - xcrun notarytool store-credentials captionoverlay-notary \
#       --apple-id <apple-id> --team-id V5HJQY5VQR
#     (an existing profile for another app of the same team works too; set PROFILE below)
#
# The everyday build-app.sh stays Apple-Development-signed (the granted
# permissions hang on that identity); this script re-signs a COPY, so the
# local dev install is untouched. Run it in your own terminal.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: release.sh <version> <build>}"
BUILDNUM="${2:?usage: release.sh <version> <build>}"
PROFILE="${NOTARY_PROFILE:-captionoverlay-notary}"

DEVID="$(security find-identity -v -p codesigning 2>/dev/null \
  | awk -F'"' '/Developer ID Application/ {print $2; exit}')"
if [[ -z "${DEVID}" ]]; then
  echo "ERROR: no 'Developer ID Application' certificate in the Keychain."
  echo "Create one in Xcode > Settings > Accounts > Manage Certificates."
  exit 1
fi
if ! xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
  echo "ERROR: notary credentials '$PROFILE' missing. Run:"
  echo "  xcrun notarytool store-credentials $PROFILE \\"
  echo "    --apple-id <your-apple-id> --team-id ${DEVID##* (}"
  echo "or set NOTARY_PROFILE to an existing profile of the same team."
  exit 1
fi

Scripts/build-app.sh

OUT="build/release"
APP="$OUT/CaptionOverlay.app"
rm -rf "$OUT"
mkdir -p "$OUT"
ditto "build/CaptionOverlay.app" "$APP"

/usr/libexec/PlistBuddy \
  -c "Set :CFBundleShortVersionString $VERSION" \
  -c "Set :CFBundleVersion $BUILDNUM" \
  "$APP/Contents/Info.plist"

# --timestamp is required for notarization (build-app.sh omits it: dev
# builds need no time-stamp server round trip).
codesign --force --timestamp --options runtime --sign "${DEVID}" "$APP"

# Notarize the app (as a zip), then staple the verdict into the app; the
# DMG is built from the stapled app so it works on an offline Mac too.
ZIP="$OUT/CaptionOverlay-$VERSION.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "notarizing app (usually 1-5 min)..."
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"
rm "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

# DMG: app plus /Applications link, signed, notarized, stapled.
DMG="$OUT/CaptionOverlay-$VERSION.dmg"
STAGE="$(mktemp -d)"
ditto "$APP" "$STAGE/CaptionOverlay.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "CaptionOverlay" -srcfolder "$STAGE" -ov \
  -format UDZO -quiet "$DMG"
rm -rf "$STAGE"
codesign --force --timestamp --sign "${DEVID}" "$DMG"
echo "notarizing DMG..."
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"

spctl --assess --type open --context context:primary-signature -v "$DMG" 2>&1 | sed 's/^/gatekeeper: /'
du -h "$DMG" "$ZIP"
echo "release files in $PWD/$OUT"
echo "next: git tag v$VERSION && gh release create v$VERSION $DMG --title \"CaptionOverlay $VERSION\" --notes-file <notes>"

#!/bin/zsh
# Build CaptionOverlay.app (Apple Silicon, macOS 26+) into build/.
#
# Signs with the Apple Development certificate when one exists, so the
# signature, and with it the granted permissions (System Audio Recording,
# Speech Recognition), stays the same across rebuilds.
set -euo pipefail
cd "$(dirname "$0")/.."

# No index store: it is only for editors and costs about 1 GB of disk.
BUILD=(swift build -c release --arch arm64 --disable-index-store)
"${BUILD[@]}"

# Ask SwiftPM where the product landed instead of hard-coding the path.
BIN="$("${BUILD[@]}" --show-bin-path)/CaptionOverlay"
[[ -x "$BIN" ]] || { echo "binary missing: $BIN" >&2; exit 1; }
# The product must be newer than every source file.
NEWEST_SRC="$(find Sources -name '*.swift' -newer "$BIN" | head -1)"
[[ -z "$NEWEST_SRC" ]] || { echo "stale product: $NEWEST_SRC is newer than $BIN" >&2; exit 1; }

APP="build/CaptionOverlay.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/CaptionOverlay"
cp Resources/CaptionOverlay.icns "$APP/Contents/Resources/CaptionOverlay.icns"
# The .lproj folders in Contents/Resources are what make the German text
# and the localized permission prompts resolve (main-bundle lookup).
for lproj in Resources/*.lproj; do
  ditto "$lproj" "$APP/Contents/Resources/$(basename "$lproj")"
done

# No LSUIElement: the app shows its Dock icon. The bundle identifier is
# fixed; changing it resets the granted permissions.
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key><string>en</string>
	<key>CFBundleLocalizations</key>
	<array>
		<string>en</string><string>de</string>
	</array>
	<key>CFBundleExecutable</key><string>CaptionOverlay</string>
	<key>CFBundleIdentifier</key><string>app.captionoverlay.mac</string>
	<key>CFBundleName</key><string>CaptionOverlay</string>
	<key>CFBundleDisplayName</key><string>CaptionOverlay</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleIconFile</key><string>CaptionOverlay</string>
	<key>CFBundleShortVersionString</key><string>0.1</string>
	<key>CFBundleVersion</key><string>1</string>
	<key>LSMinimumSystemVersion</key><string>26.0</string>
	<key>LSArchitecturePriority</key>
	<array><string>arm64</string></array>
	<key>NSHighResolutionCapable</key><true/>
	<key>NSAudioCaptureUsageDescription</key>
	<string>CaptionOverlay listens to the sound your Mac plays to show it as captions. Nothing is recorded or sent anywhere.</string>
	<key>NSSpeechRecognitionUsageDescription</key>
	<string>CaptionOverlay turns the sound your Mac plays into captions, on this Mac only.</string>
</dict>
</plist>
PLIST

# Select by hash, not name: two same-name "Apple Development"
# certificates make a name-based codesign fail as "ambiguous".
IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
  | awk '/Apple Development/ {print $2; exit}')"
if [[ -n "${IDENTITY}" ]]; then
  echo "signing with: ${IDENTITY}"
else
  IDENTITY="-"
  echo "no Apple Development identity: ad-hoc signing (permissions will not survive rebuilds)"
fi
codesign --force --options runtime --sign "${IDENTITY}" "$APP"

codesign -dv "$APP" 2>&1 | grep -E "Identifier|Format" || true
lipo -info "$APP/Contents/MacOS/CaptionOverlay"
echo "built: $PWD/$APP"

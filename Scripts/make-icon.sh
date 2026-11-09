#!/bin/zsh
# Renders Resources/CaptionOverlay.icns from Scripts/draw-icon.swift.
# Run by hand after changing the artwork; the .icns is checked in so
# build-app.sh needs no Swift-script step.
set -euo pipefail
cd "$(dirname "$0")/.."

ICONSET="$(mktemp -d)/CaptionOverlay.iconset"
mkdir -p "$ICONSET" Resources
swift Scripts/draw-icon.swift "$ICONSET"
iconutil -c icns "$ICONSET" -o Resources/CaptionOverlay.icns
echo "wrote: $PWD/Resources/CaptionOverlay.icns"

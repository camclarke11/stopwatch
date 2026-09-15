#!/bin/zsh
# Regenerate Source/AppIcon.icns from the cat sprite. Run after changing the sitting cat.
set -euo pipefail
cd "${0:A:h:h}"
folder=$(mktemp -d)
trap 'rm -rf -- "$folder"' EXIT
./Scripts/swiftc.sh Scripts/make-icon.swift -o "$folder/make-icon"
mkdir "$folder/AppIcon.iconset"
"$folder/make-icon" Source/pixel-cat.js "$folder/AppIcon.iconset"
iconutil -c icns "$folder/AppIcon.iconset" -o Source/AppIcon.icns
cp "$folder/AppIcon.iconset/icon_512x512@2x.png" "${TMPDIR:-/tmp/}stopwatch-icon-preview.png"
print "Wrote Source/AppIcon.icns"

#!/bin/zsh
set -eu
cd "${0:A:h}"
version=$(cat VERSION)
[[ "$version" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || { print -u2 'Invalid VERSION'; exit 1; }
mkdir -p Stopwatch.app/Contents/MacOS Stopwatch.app/Contents/Resources
xcrun swiftc Source/main.swift Source/TimerState.swift Source/GitUpdater.swift -o Stopwatch.app/Contents/MacOS/Stopwatch -framework Cocoa -framework WebKit -framework CoreText -module-cache-path /tmp/stopwatch-module-cache
cp Source/index.html Source/pixel-cat.js Source/rolling.js Source/rolling.css Source/ROLLING-LICENSE Source/fonts.css Source/flap-font.css Stopwatch.app/Contents/Resources/
cp -R Source/Fonts Source/Backgrounds Stopwatch.app/Contents/Resources/
cp Scripts/git-update.sh Scripts/replace-app.sh Stopwatch.app/Contents/Resources/
if [[ -n "${STOPWATCH_CHECKOUT:-}" ]]; then
  print -rn -- "$STOPWATCH_CHECKOUT" > Stopwatch.app/Contents/Resources/GitCheckout.txt
else
  rm -f Stopwatch.app/Contents/Resources/GitCheckout.txt
fi
cat > Stopwatch.app/Contents/Info.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleExecutable</key><string>Stopwatch</string><key>CFBundleIdentifier</key><string>dev.camclarke.stopwatch</string><key>CFBundleName</key><string>Stopwatch</string><key>CFBundlePackageType</key><string>APPL</string><key>CFBundleShortVersionString</key><string>$version</string><key>CFBundleVersion</key><string>$version</string><key>LSMinimumSystemVersion</key><string>13.0</string><key>NSHighResolutionCapable</key><true/></dict></plist>
PLIST
codesign --force --sign - Stopwatch.app

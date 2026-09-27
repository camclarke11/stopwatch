#!/bin/zsh
set -eu
cd "${0:A:h}"
version=$(cat VERSION)
[[ "$version" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || { print -u2 'Invalid VERSION'; exit 1; }
rm -rf Stewie.app Stopwatch.app
mkdir -p Stewie.app/Contents/MacOS Stewie.app/Contents/Resources
./Scripts/swiftc.sh Source/main.swift Source/TimerState.swift Source/GitUpdater.swift -o Stewie.app/Contents/MacOS/Stewie -framework Cocoa -framework WebKit -framework CoreText
cp Source/index.html Source/pixel-cat.js Source/rolling.js Source/rolling.css Source/ROLLING-LICENSE Source/fonts.css Source/flap-font.css Source/AppIcon.icns Stewie.app/Contents/Resources/
cp -R Source/Fonts Source/Backgrounds Stewie.app/Contents/Resources/
cp Scripts/git-update.sh Scripts/replace-app.sh Scripts/migrate-app.sh Stewie.app/Contents/Resources/
if [[ -n "${STOPWATCH_CHECKOUT:-}" ]]; then
  print -rn -- "$STOPWATCH_CHECKOUT" > Stewie.app/Contents/Resources/GitCheckout.txt
else
  rm -f Stewie.app/Contents/Resources/GitCheckout.txt
fi
cat > Stewie.app/Contents/Info.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleExecutable</key><string>Stewie</string><key>CFBundleIconFile</key><string>AppIcon</string><key>CFBundleIdentifier</key><string>dev.camclarke.stopwatch</string><key>CFBundleName</key><string>Stewie</string><key>CFBundleDisplayName</key><string>Stewie</string><key>CFBundlePackageType</key><string>APPL</string><key>CFBundleShortVersionString</key><string>$version</string><key>CFBundleVersion</key><string>$version</string><key>LSMinimumSystemVersion</key><string>13.0</string><key>NSHighResolutionCapable</key><true/></dict></plist>
PLIST
codesign --force --sign - Stewie.app
# Older Stopwatch updaters require this build path. The new app moves itself to Stewie.app on first launch.
/usr/bin/ditto Stewie.app Stopwatch.app

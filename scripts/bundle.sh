#!/bin/zsh
# Собирает «WPhoto.app» в build/ (без Xcode, только SwiftPM).
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP="build/WPhoto.app"
VERSION="${VERSION:-0.3}"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/en.lproj" "$APP/Contents/Resources/ru.lproj"
cp .build/release/WPhoto "$APP/Contents/MacOS/WPhoto"

# Иконка программы: рисуем кодом и собираем .icns.
ICONSET=build/AppIcon.iconset
rm -rf "$ICONSET"
swiftc -O -o build/appicon scripts/appicon/main.swift
build/appicon "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>WPhoto</string>
<key>CFBundleDisplayName</key><string>WPhoto</string>
<key>CFBundleIdentifier</key><string>dev.oleg.wphoto</string>
<key>CFBundleExecutable</key><string>WPhoto</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleLocalizations</key><array><string>en</string><string>ru</string></array>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSApplicationCategoryType</key><string>public.app-category.photography</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
<key>CFBundleDocumentTypes</key><array><dict>
  <key>CFBundleTypeName</key><string>Image</string>
  <key>CFBundleTypeRole</key><string>Viewer</string>
  <key>LSHandlerRank</key><string>Alternate</string>
  <key>LSItemContentTypes</key><array><string>public.image</string></array>
</dict></array>
<key>NSDesktopFolderUsageDescription</key><string>WPhoto shows pictures from your Desktop folder.</string>
<key>NSDocumentsFolderUsageDescription</key><string>WPhoto shows pictures from your Documents folder.</string>
<key>NSDownloadsFolderUsageDescription</key><string>WPhoto shows pictures from your Downloads folder.</string>
<key>NSRemovableVolumesUsageDescription</key><string>WPhoto shows pictures from removable drives.</string>
<key>NSNetworkVolumesUsageDescription</key><string>WPhoto shows pictures from network drives.</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Готово: $APP"

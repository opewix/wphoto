#!/bin/zsh
# Собирает установочный образ build/wphoto-<версия>.dmg: приложение + ярлык «Программы».
set -euo pipefail
cd "$(dirname "$0")/.."
export VERSION="${VERSION:-0.3}"
./scripts/bundle.sh

STAGE=build/dmg
DMG="build/wphoto-$VERSION.dmg"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "build/WPhoto.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

hdiutil create -volname "WPhoto $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
echo "Установщик: $DMG"

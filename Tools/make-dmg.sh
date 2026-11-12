#!/bin/sh
# Builds Dormer.app in Release (ad-hoc signed, hardened runtime) and packs it into build/Dormer-<version>.dmg
# with a shortcut to /Applications. Prints the SHA-256 and writes it next to the image.
# Usage: Tools/make-dmg.sh [version]   (defaults to MARKETING_VERSION from the Xcode project)
set -eu
cd "$(dirname "$0")/.."

VERSION=${1:-$(sed -n 's/.*MARKETING_VERSION = \(.*\);/\1/p' Dormer.xcodeproj/project.pbxproj | head -1)}
DERIVED=build/DerivedData-release
DMG="build/Dormer-$VERSION.dmg"

xcodebuild -project Dormer.xcodeproj -scheme Dormer -configuration Release \
    -derivedDataPath "$DERIVED" MARKETING_VERSION="$VERSION" build
APP="$DERIVED/Build/Products/Release/Dormer.app"
[ -d "$APP" ] || { echo "Dormer.app was not built" >&2; exit 1; }

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/Dormer.app"
ln -s /Applications "$STAGE/Applications"

mkdir -p build
rm -f "$DMG"
hdiutil create -volname "Dormer" -srcfolder "$STAGE" -format UDZO -ov "$DMG" >/dev/null
(cd build && shasum -a 256 "Dormer-$VERSION.dmg" | tee "Dormer-$VERSION.dmg.sha256")
echo "Created $DMG"

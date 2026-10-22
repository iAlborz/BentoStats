#!/bin/bash
# Archives Bento Stats for the Mac App Store, as Xcode's Product › Archive would, and
# puts the archive where Xcode's Organizer lists it:
#
#   Scripts/appstore.sh   → ~/Library/Developer/Xcode/Archives/<date>/Bento Stats <date, time>.xcarchive
#
# Then, in Xcode: Window › Organizer › Archives › Bento Stats › Distribute App ›
# App Store Connect. Organizer signs the app for distribution with the team's certificate
# and an App Store profile, creating them if they do not exist yet, and uploads it.
#
# The archive holds a copy of the release build with the App Store bundle ID, signed with
# the team's Apple Development certificate and the sandbox entitlements in
# Resources/AppStore.entitlements; Organizer keeps those entitlements when it re-signs.
# The local build keeps its own bundle ID and stays outside the sandbox.
set -euo pipefail

cd "$(dirname "$0")/.."

BUNDLE_ID="${BUNDLE_ID:-io.github.ialborz.bentostats}"
TEAM="${TEAM:-R3S425S3T8}"
IDENTITY="${IDENTITY:-Apple Development: Alborz Heydaryan (6K967VP868)}"

security find-identity -v -p codesigning | grep -qF "$IDENTITY" \
  || { echo "error: no \"$IDENTITY\" certificate in the keychain (set IDENTITY=…)" >&2; exit 1; }

NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' Resources/Info.plist)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Resources/Info.plist)"

BUILT="$(Scripts/build.sh release | tail -1)"
BIN_DIR="$(swift build -c release --show-bin-path)"

ARCHIVE="$HOME/Library/Developer/Xcode/Archives/$(date +%Y-%m-%d)/$NAME $(date '+%Y-%m-%d, %-I.%M %p').xcarchive"
APP="$ARCHIVE/Products/Applications/$NAME.app"
mkdir -p "$ARCHIVE/Products/Applications" "$ARCHIVE/dSYMs"
cp -R "$BUILT" "$APP"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP/Contents/Info.plist"

# The UI's resource bundle, unpacked into the app's own Resources, where Logo looks
# first. Organizer re-signs the app but leaves a bundle nested in Resources as it was,
# and App Store Connect refuses one that is not signed for distribution (ITMS-90284).
mv "$APP/Contents/Resources/AirStats_AirStatUI.bundle/Contents/Resources/"* "$APP/Contents/Resources/"
rm -rf "$APP/Contents/Resources/AirStats_AirStatUI.bundle"

# Symbols, so crash reports from App Store users can be read.
dsymutil "$BIN_DIR/AirStats" -o "$ARCHIVE/dSYMs/$NAME.app.dSYM"

codesign --force --sign "$IDENTITY" --entitlements Resources/AppStore.entitlements "$APP"
codesign --verify --deep --strict "$APP"

PLIST="$ARCHIVE/Info.plist"
/usr/libexec/PlistBuddy \
  -c "Add :ArchiveVersion integer 2" \
  -c "Add :CreationDate date $(date -u '+%a %b %d %H:%M:%S GMT %Y')" \
  -c "Add :Name string $NAME" \
  -c "Add :SchemeName string $NAME" \
  -c "Add :ApplicationProperties dict" \
  -c "Add :ApplicationProperties:ApplicationPath string Applications/$NAME.app" \
  -c "Add :ApplicationProperties:Architectures array" \
  -c "Add :ApplicationProperties:Architectures:0 string $(lipo -archs "$APP/Contents/MacOS/AirStats")" \
  -c "Add :ApplicationProperties:CFBundleIdentifier string $BUNDLE_ID" \
  -c "Add :ApplicationProperties:CFBundleShortVersionString string $VERSION" \
  -c "Add :ApplicationProperties:CFBundleVersion string $BUILD" \
  -c "Add :ApplicationProperties:SigningIdentity string $IDENTITY" \
  -c "Add :ApplicationProperties:Team string $TEAM" \
  "$PLIST"

echo "$ARCHIVE"

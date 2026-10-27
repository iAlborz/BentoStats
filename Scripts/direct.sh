#!/bin/bash
# Packages the full Bento Stats, temperatures and fan speeds included, for download
# outside the Mac App Store: signed with the team's Developer ID, notarized, stapled,
# and put in a .dmg.
#
#   Scripts/direct.sh   → dist/BentoStats.dmg, and dist/BentoStats.zip for the updater
#
# The store's copy runs in the App Sandbox, which closes the SMC; this one is archived
# with no entitlements, so it stays outside it. Xcode does the signing and notarizing:
# exporting the archive for Developer ID makes the certificate in the cloud if the team
# has none, and uploads the app to Apple's notary service under the account signed in
# to Xcode, so this Mac needs no certificate or notarytool profile of its own.
#
# This copy checks the repository's latest release once a day and offers to install it
# (Updater in AirStatUI). Publish both files, under these names, on a release tagged
# v<CFBundleShortVersionString>: the .dmg for people, the .zip for installed copies.
set -euo pipefail

cd "$(dirname "$0")/.."

NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' Resources/Info.plist)"
TEAM="${TEAM:-R3S425S3T8}"
WORK="dist/direct"
DMG="dist/BentoStats.dmg"
ZIP="dist/BentoStats.zip"

rm -rf "$WORK" "$DMG" "$ZIP"
mkdir -p "$WORK"

ARCHIVE="$(ARCHIVE="$PWD/$WORK/$NAME.xcarchive" ENTITLEMENTS= \
  RELEASES_URL="https://api.github.com/repos/iAlborz/BentoStats/releases/latest" \
  Scripts/appstore.sh | tail -1)"

cat > "$WORK/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key><string>developer-id</string>
	<key>destination</key><string>upload</string>
	<key>teamID</key><string>$TEAM</string>
	<key>signingStyle</key><string>automatic</string>
</dict>
</plist>
EOF

xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$WORK/ExportOptions.plist" \
  -exportPath "$WORK/upload" -allowProvisioningUpdates

# Apple usually answers within a few minutes. Until it has, there is no notarized app
# to export and this fails, so it is retried rather than waited on once.
for _ in $(seq 60); do
  if xcodebuild -exportNotarizedApp -archivePath "$ARCHIVE" -exportPath "$WORK/notarized" >/dev/null 2>&1; then
    break
  fi
  sleep 30
done
APP="$WORK/notarized/$NAME.app"
[ -d "$APP" ] || { echo "error: Apple has not notarized $ARCHIVE after 30 minutes" >&2; exit 1; }

# What Gatekeeper will decide on a Mac that downloaded it.
xcrun stapler validate "$APP"
spctl --assess --type execute -v "$APP"

# Scripts/dmg.py lays the window out: the app beside an Applications shortcut, over
# Resources/dmg-background.tiff. The image itself is not signed, which Gatekeeper does
# not ask of a disk image; it checks the stapled app inside when it first opens.
python3 -m venv "$WORK/venv"
"$WORK/venv/bin/pip" install --quiet dmgbuild
"$WORK/venv/bin/dmgbuild" -s Scripts/dmg.py -D app="$APP" -D root="$PWD" "$NAME" "$DMG" >/dev/null

# What an installed copy downloads to update itself. ditto keeps the signature and the
# stapled ticket intact, as the Finder's Compress would not.
ditto -c -k --keepParent "$APP" "$ZIP"

echo "$DMG"
echo "$ZIP"

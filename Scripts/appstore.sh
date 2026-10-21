#!/bin/bash
# Builds Bento Stats for the Mac App Store: sandboxed, signed for distribution, and
# wrapped in the signed installer package App Store Connect takes.
#
#   BUNDLE_ID=com.example.BentoStats Scripts/appstore.sh   → dist/Bento Stats.pkg
#
# Then upload the .pkg with Apple's Transporter app.
#
# One-time setup, in the Apple Developer account and in Xcode:
#   - An App ID for BUNDLE_ID, and a Mac App Store provisioning profile for it, saved
#     as dist/AppStore.provisionprofile or passed as PROFILE=path.
#   - "Apple Distribution" and "Mac Installer Distribution" certificates in the
#     keychain: Xcode › Settings › Accounts › Manage Certificates. The installer one
#     appears in the keychain as "3rd Party Mac Developer Installer".
#   - The app's record in App Store Connect, under the same bundle ID.
#
# The local build keeps its own bundle ID and stays outside the sandbox; only the copy
# made here is changed. Resources/AppStore.entitlements says what the sandbox allows.
set -euo pipefail

cd "$(dirname "$0")/.."

BUNDLE_ID="${BUNDLE_ID:?set BUNDLE_ID to the App ID registered for the App Store}"
PROFILE="${PROFILE:-dist/AppStore.provisionprofile}"
APP_IDENTITY="${APP_IDENTITY:-Apple Distribution}"
INSTALLER_IDENTITY="${INSTALLER_IDENTITY:-3rd Party Mac Developer Installer}"
DIST="dist"
APP="$DIST/Bento Stats.app"
PKG="$DIST/Bento Stats.pkg"

# Preflight, so a missing piece of setup is named before a two-minute build.
[ -f "$PROFILE" ] || { echo "error: no provisioning profile at $PROFILE (set PROFILE=…)" >&2; exit 1; }
security find-identity -v -p codesigning | grep -q "$APP_IDENTITY" \
  || { echo "error: no \"$APP_IDENTITY\" certificate in the keychain" >&2; exit 1; }
security find-identity -v | grep -q "$INSTALLER_IDENTITY" \
  || { echo "error: no \"$INSTALLER_IDENTITY\" certificate in the keychain" >&2; exit 1; }

# The profile names the team and the app; the signature must carry both, or App Store
# Connect refuses the upload.
PROFILE_PLIST="$(mktemp)"
security cms -D -i "$PROFILE" > "$PROFILE_PLIST"
TEAM="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.developer.team-identifier' "$PROFILE_PLIST")"
APP_IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.application-identifier' "$PROFILE_PLIST")"
[ "$APP_IDENTIFIER" = "$TEAM.$BUNDLE_ID" ] \
  || { echo "error: $PROFILE is for $APP_IDENTIFIER, not $TEAM.$BUNDLE_ID" >&2; exit 1; }

ENTITLEMENTS="$(mktemp -d)/AppStore.entitlements"
cp Resources/AppStore.entitlements "$ENTITLEMENTS"
/usr/libexec/PlistBuddy \
  -c "Add :com.apple.application-identifier string $APP_IDENTIFIER" \
  -c "Add :com.apple.developer.team-identifier string $TEAM" \
  "$ENTITLEMENTS"

BUILT="$(Scripts/build.sh release | tail -1)"
mkdir -p "$DIST"
rm -rf "$APP" "$PKG"
cp -R "$BUILT" "$APP"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP/Contents/Info.plist"
cp "$PROFILE" "$APP/Contents/embedded.provisionprofile"

codesign --force --sign "$APP_IDENTITY" --entitlements "$ENTITLEMENTS" "$APP"
codesign --verify --strict --verbose=2 "$APP"

productbuild --component "$APP" /Applications --sign "$INSTALLER_IDENTITY" "$PKG"

echo "$PKG"

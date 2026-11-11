#!/usr/bin/env bash
#
# release.sh: build, Developer ID sign, check, notarize, staple and package
# Cloudpane as a universal .zip and a .dmg, with their SHA-256 checksums.
#
# Prerequisites (one time):
#   1. The certificate "Developer ID Application: 404 Cybersecurity LLC
#      (YA83Q8FTH3)" in the keychain. The team has a second Developer ID
#      certificate; this script refuses any other signer.
#   2. A stored notarytool credential profile for the team:
#
#        xcrun notarytool store-credentials "switchback-notary" --team-id YA83Q8FTH3
#
#   3. XcodeGen (brew install xcodegen).
#
# Usage:
#   scripts/release.sh                          # full release into dist/
#   NOTARY_PROFILE=my-profile scripts/release.sh
#   SKIP_NOTARIZE=1 scripts/release.sh          # dry run: stop after signing and the checks
#
# A full release needs every tracked file committed, so the commit printed at
# the end is exactly what was built. Tag that commit v<version>.
#
set -euo pipefail
cd "$(dirname "$0")/.."

NOTARY_PROFILE="${NOTARY_PROFILE:-switchback-notary}"
SKIP_NOTARIZE="${SKIP_NOTARIZE:-0}"
TEAM="YA83Q8FTH3"
SIGN_NAME="Developer ID Application: 404 Cybersecurity LLC (YA83Q8FTH3)"
# Must match signingCertificate in scripts/ExportOptions.plist.
SIGN_SHA="7833623A279DB2E5895C322A78BE1E051AB56B7C"
BUNDLE_ID="com.404tools.cloudpane"
SCHEME="Cloudpane"
PROJECT="Cloudpane.xcodeproj"
BUILD_DIR="build/release"
DERIVED="$BUILD_DIR/DerivedData"
ARCHIVE="$BUILD_DIR/Cloudpane.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
APP="$EXPORT_DIR/Cloudpane.app"
BIN="$APP/Contents/MacOS/Cloudpane"

fail() { echo "error: $*" >&2; exit 1; }

# Runs a long command with its output in a log file, and shows the end of the
# log if it fails.
logged() {
  local log="$1"; shift
  if ! "$@" >"$log" 2>&1; then
    tail -n 40 "$log" >&2
    fail "$1 failed; full log in $log"
  fi
}

command -v xcodegen >/dev/null || fail "xcodegen not found (brew install xcodegen)"
security find-identity -v -p codesigning | grep -q "$SIGN_SHA" \
  || fail "certificate $SIGN_SHA ($SIGN_NAME) is not in the keychain"
grep -q "$SIGN_SHA" scripts/ExportOptions.plist \
  || fail "scripts/ExportOptions.plist does not name certificate $SIGN_SHA"

# The Xcode project is generated from project.yml.
xcodegen generate >/dev/null

# Hidden files and folders on disk are local state and must never reach the
# project file. XcodeGen adds a hidden folder it finds inside a source folder.
if grep -n -E 'path = "?\.[^.]' "$PROJECT/project.pbxproj" >&2; then
  fail "$PROJECT/project.pbxproj references a hidden file or folder; exclude it in project.yml"
fi

if ! git diff --quiet HEAD --; then
  if [ "$SKIP_NOTARIZE" = "1" ]; then
    echo "warning: uncommitted changes; fine for a dry run, not for a release" >&2
  else
    git status --short >&2
    fail "uncommitted changes to tracked files. Commit first, so the release matches a commit."
  fi
fi
COMMIT="$(git rev-parse HEAD)"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# CloudpaneCore is fetched from GitHub. -scmProvider system makes xcodebuild
# use git's own credentials, which a private repository needs.
echo "==> Running unit tests"
logged "$BUILD_DIR/test.log" xcodebuild test -project "$PROJECT" -scheme "$SCHEME" \
  -scmProvider system -derivedDataPath "$DERIVED" -destination 'platform=macOS'
TESTS="$(sed -n 's/.*Executed \([0-9][0-9]*\) tests*, with 0 failures.*/\1/p' "$BUILD_DIR/test.log" | sort -n | tail -n 1)"
[ -n "$TESTS" ] && [ "$TESTS" -gt 0 ] || fail "no tests ran; see $BUILD_DIR/test.log"
echo "    $TESTS tests passed"

echo "==> Archiving (universal)"
logged "$BUILD_DIR/archive.log" xcodebuild archive -project "$PROJECT" -scheme "$SCHEME" \
  -configuration Release -scmProvider system -derivedDataPath "$DERIVED" \
  -destination 'generic/platform=macOS' -archivePath "$ARCHIVE" \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO DEVELOPMENT_TEAM="$TEAM"

echo "==> Exporting the Developer ID signed app"
logged "$BUILD_DIR/export.log" xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" -exportOptionsPlist scripts/ExportOptions.plist
[ -x "$BIN" ] || fail "export produced no app at $APP"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
[ -n "$VERSION" ] || fail "could not read the version from the exported app"
echo "    Cloudpane $VERSION ($BUILD)"

# ---- Checks. Every one must pass before anything is sent to Apple. ----

echo "==> Check: signature"
codesign --verify --deep --strict --verbose=2 "$APP" || fail "the signature does not verify"
SIGNATURE="$(codesign -dvv "$APP" 2>&1)"
echo "$SIGNATURE" | grep -E '^(Identifier|Authority|TeamIdentifier|Timestamp)=|flags=' | sed 's/^/    /'
# The first Authority line is the certificate that signed the app.
AUTHORITY="$(echo "$SIGNATURE" | sed -n 's/^Authority=//p' | head -n 1)"
[ "$AUTHORITY" = "$SIGN_NAME" ] \
  || fail "signed by '$AUTHORITY', expected '$SIGN_NAME'"
echo "$SIGNATURE" | grep -q "^TeamIdentifier=$TEAM\$" || fail "team identifier is not $TEAM"
echo "$SIGNATURE" | grep -q "^Identifier=$BUNDLE_ID\$" || fail "bundle identifier is not $BUNDLE_ID"

echo "==> Check: hardened runtime"
echo "$SIGNATURE" | grep -E -q '^CodeDirectory .*flags=0x[0-9a-f]+\([a-z,-]*runtime[a-z,-]*\)' \
  || fail "the hardened runtime flag is not set"

echo "==> Check: nothing nested to sign"
# CloudpaneCore is linked statically, so the main executable is the only code.
MACHO="$(find "$APP" -type f -exec sh -c 'file -b "$1" | grep -q "Mach-O" && echo "$1"' _ {} \;)"
[ "$MACHO" = "$BIN" ] || fail "expected one Mach-O file ($BIN), found: $MACHO"
HIDDEN="$(find "$APP" -name '.*')"
[ -z "$HIDDEN" ] || fail "hidden files inside the app: $HIDDEN"

echo "==> Check: entitlements"
ENTITLEMENTS="$BUILD_DIR/entitlements.plist"
codesign -d --entitlements - --xml "$APP" >"$ENTITLEMENTS" 2>/dev/null
[ -s "$ENTITLEMENTS" ] || fail "the signed app carries no entitlements"
# The team and application identifiers are not capabilities; codesign may add
# them. Anything else beyond the four is refused.
ACTUAL="$(plutil -p "$ENTITLEMENTS" \
  | grep -v -x "  \"com.apple.application-identifier\" => \"$TEAM.$BUNDLE_ID\"" \
  | grep -v -x "  \"com.apple.developer.team-identifier\" => \"$TEAM\"" \
  | LC_ALL=C sort)"
EXPECTED="$(LC_ALL=C sort <<'ENTITLEMENTS_END'
{
  "com.apple.security.app-sandbox" => true
  "com.apple.security.files.bookmarks.app-scope" => true
  "com.apple.security.files.downloads.read-write" => true
  "com.apple.security.files.user-selected.read-only" => true
}
ENTITLEMENTS_END
)"
plutil -p "$ENTITLEMENTS" | sed 's/^/    /'
if grep -q "com.apple.security.network" "$ENTITLEMENTS"; then
  fail "the signed app has a network entitlement"
fi
[ "$ACTUAL" = "$EXPECTED" ] || fail "entitlements are not exactly the four expected"

echo "==> Check: no demo mode in the binary"
STRINGS="$(strings -a -arch all "$BIN")" || fail "strings could not read $BIN"
DEMO="$(printf '%s\n' "$STRINGS" | grep -c CloudpaneDemo || true)"
[ "$DEMO" = "0" ] || fail "the binary contains CloudpaneDemo $DEMO times; demo mode must not ship"
echo "    CloudpaneDemo count: $DEMO"

echo "==> Check: architectures"
ARCHS_FOUND="$(lipo -archs "$BIN" | tr ' ' '\n' | LC_ALL=C sort | tr '\n' ' ' | sed 's/ *$//')"
[ "$ARCHS_FOUND" = "arm64 x86_64" ] || fail "architectures are '$ARCHS_FOUND', expected 'arm64 x86_64'"
echo "    $ARCHS_FOUND"

echo "==> Check: build number"
[ -n "$BUILD" ] && [ "$BUILD" != "0" ] || fail "CFBundleVersion is '$BUILD'; the build number was not stamped"
echo "    $BUILD"

if [ "$SKIP_NOTARIZE" = "1" ]; then
  echo "==> SKIP_NOTARIZE=1: every check passed. Stopping before notarization; nothing written to dist/."
  echo "    Signed app: $APP"
  exit 0
fi

# ---- Notarize and package. ----

# Everything is built under $BUILD_DIR and moved into dist/ only at the end, so a
# failed run never leaves a half-finished release there.
OUT="$BUILD_DIR/out"
ZIP="$OUT/Cloudpane-$VERSION.zip"
DMG="$OUT/Cloudpane-$VERSION.dmg"
mkdir -p "$OUT"

# notarytool can exit 0 for a submission Apple rejected, so read the status.
notarize() {
  local log="$BUILD_DIR/notary-$(basename "$1").log"
  xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait | tee "$log"
  grep -q "status: Accepted" "$log" || fail "notarization of $1 was not accepted; see $log"
}

echo "==> Notarizing the app"
ditto -c -k --keepParent "$APP" "$BUILD_DIR/notary-app.zip"
notarize "$BUILD_DIR/notary-app.zip"

echo "==> Stapling the app"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl -a -vv -t exec "$APP"

echo "==> Packaging $ZIP (stapled app)"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> Building $DMG"
STAGE="$BUILD_DIR/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Cloudpane" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG"
codesign --sign "$SIGN_SHA" --timestamp "$DMG"

echo "==> Notarizing and stapling the dmg"
notarize "$DMG"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl -a -vv -t open --context context:primary-signature "$DMG"

echo "==> Checksums"
(cd "$OUT" && shasum -a 256 "Cloudpane-$VERSION.zip" "Cloudpane-$VERSION.dmg" >SHA256SUMS.txt)
sed 's/^/    /' "$OUT/SHA256SUMS.txt"

# The build took minutes; make sure the checkout is still the commit it started from.
[ "$(git rev-parse HEAD)" = "$COMMIT" ] || fail "HEAD moved during the build; run again"
git diff --quiet HEAD -- || fail "tracked files changed during the build; run again"

mkdir -p dist
rm -f "dist/Cloudpane-$VERSION.zip" "dist/Cloudpane-$VERSION.dmg" dist/SHA256SUMS.txt
mv "$ZIP" "$DMG" "$OUT/SHA256SUMS.txt" dist/

echo "==> Done. Cloudpane $VERSION ($BUILD), built from commit $COMMIT"
echo "    dist/Cloudpane-$VERSION.zip"
echo "    dist/Cloudpane-$VERSION.dmg"
echo "    dist/SHA256SUMS.txt"
echo "    Tag the built commit: git tag v$VERSION $COMMIT"

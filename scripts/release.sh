#!/bin/zsh
# Builds, signs with Developer ID, notarizes and staples Koffein, then zips it for a GitHub release.
#
# One-time setup:
#   1. Xcode → Settings → Accounts → Manage Certificates → + → Developer ID Application
#   2. xcrun notarytool store-credentials koffein --apple-id <you> --team-id <TEAM>
#
# Usage: VERSION=1.0 scripts/release.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION:?Set VERSION, e.g. VERSION=1.0}"
PROFILE="${NOTARY_PROFILE:-koffein}"
IDENTITY="$(security find-identity -v -p codesigning | sed -nE 's/.*"(Developer ID Application: [^"]+)".*/\1/p' | head -1)"
[[ -n "$IDENTITY" ]] || { echo "No Developer ID Application certificate in the keychain. See the setup notes at the top of this script." >&2; exit 1; }

OUT="$ROOT/dist"
ZIP="$OUT/Koffein-$VERSION.zip"
mkdir -p "$OUT"

SIGN_IDENTITY="$IDENTITY" VERSION="$VERSION" NO_OPEN=1 "$ROOT/build-app.sh"

# notarytool takes a zip; the stapled app is zipped again for distribution.
ditto -c -k --keepParent "$ROOT/Koffein.app" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$ROOT/Koffein.app"
rm "$ZIP"
ditto -c -k --keepParent "$ROOT/Koffein.app" "$ZIP"
spctl --assess --type execute --verbose "$ROOT/Koffein.app"
echo "Ready: $ZIP"

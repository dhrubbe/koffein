#!/bin/zsh
# Builds the riff gallery outside iCloud Drive (codesign rejects bundles there) and opens it.
# Pass --capture <dir> to write gallery.png plus one PNG per riff, then quit.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
STAGE="${TMPDIR:-/tmp}/koffein-riffs/Riffs.app"
mkdir -p "$STAGE/Contents/MacOS"

xcrun swiftc -parse-as-library -O -target arm64-apple-macosx27.0 \
  "$ROOT/Riffs.swift" -o "$STAGE/Contents/MacOS/Riffs"

cat > "$STAGE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>Riffs</string>
	<key>CFBundleIdentifier</key>
	<string>com.faraz.koffein.riffs</string>
	<key>CFBundleName</key>
	<string>Koffein Riffs</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
</dict>
</plist>
PLIST
codesign --force --sign - "$STAGE" 2>/dev/null

pkill -f "koffein-riffs/Riffs.app" && sleep 0.3 || true
if [[ "${1:-}" == "--capture" ]]; then
  mkdir -p "$2"
  open -W -n "$STAGE" --args --capture "$(cd "$2" && pwd)" "${@:3}"
else
  open -n "$STAGE"
fi

#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT/.build/release"
APP_DIR="$ROOT/Koffein.app"
# iCloud Drive tags bundles in ~/Documents with Finder info, which codesign rejects, so assemble and sign outside it.
STAGE="$(mktemp -d)/Koffein.app"
trap 'rm -rf "${STAGE:h}"' EXIT

mkdir -p "$BUILD_DIR" "$ROOT/.build/module-cache"
CLANG_MODULE_CACHE_PATH="$ROOT/.build/module-cache" \
SWIFT_MODULECACHE_PATH="$ROOT/.build/module-cache" \
xcrun swiftc -parse-as-library -O \
  -target arm64-apple-macosx26.0 \
  -framework AppKit -framework SwiftUI -framework IOKit -framework ServiceManagement \
  "$ROOT/Sources/Koffein/main.swift" \
  -o "$BUILD_DIR/Koffein"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"
cp "$BUILD_DIR/Koffein" "$STAGE/Contents/MacOS/Koffein"
chmod +x "$STAGE/Contents/MacOS/Koffein"

cat > "$STAGE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDisplayName</key>
	<string>Koffein</string>
	<key>CFBundleExecutable</key>
	<string>Koffein</string>
	<key>CFBundleIdentifier</key>
	<string>com.faraz.koffein</string>
	<key>CFBundleName</key>
	<string>Koffein</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>26.0</string>
	<key>LSUIElement</key>
	<true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$STAGE"

# Quit the running copy first, or `open` starts a second one next to it.
pkill -x Koffein && sleep 0.5 || true
rm -rf "$APP_DIR"
ditto "$STAGE" "$APP_DIR"
open "$APP_DIR"
echo "Built and opened $APP_DIR"

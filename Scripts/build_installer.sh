#!/bin/bash
# Builds MacDance.dmg — one command, ready to distribute.
# Usage: ./build_installer.sh [--skip-notarize]
#
# Prerequisites:
#   - Apple Developer ID certificate installed in Keychain
#   - brew install create-dmg
#   - For notarization: store App Store Connect password:
#       xcrun notarytool store-credentials "MacDance"
#         --apple-id you@email.com --team-id XXXXXXXXXX

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/.."
BUILD_DIR="$PROJECT_DIR/build"
ARCHIVE="$BUILD_DIR/MacDance.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
APP="$EXPORT_DIR/MacDance.app"
DMG="$BUILD_DIR/MacDance.dmg"
BUNDLE_ID="com.macdance.app"
SKIP_NOTARIZE=false

for arg in "$@"; do
    case $arg in
        --skip-notarize) SKIP_NOTARIZE=true ;;
    esac
done

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# --- Export options plist (temp) ---
EXPORT_PLIST="$BUILD_DIR/ExportOptions.plist"
cat > "$EXPORT_PLIST" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
</dict>
</plist>
PLIST

# --- 1. Archive ---
echo "==> Archiving..."
xcodebuild archive \
    -project "$PROJECT_DIR/MacDance.xcodeproj" \
    -scheme MacDance \
    -configuration Release \
    -archivePath "$ARCHIVE" \
    -quiet

# --- 2. Export .app ---
echo "==> Exporting app..."
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$EXPORT_PLIST" \
    -quiet

# --- 3. Notarize ---
if [ "$SKIP_NOTARIZE" = false ]; then
    echo "==> Notarizing..."
    ditto -c -k --keepParent "$APP" "$BUILD_DIR/MacDance.zip"
    xcrun notarytool submit "$BUILD_DIR/MacDance.zip" \
        --keychain-profile "MacDance" \
        --wait
    xcrun stapler staple "$APP"
    rm "$BUILD_DIR/MacDance.zip"
else
    echo "==> Skipping notarization (--skip-notarize)"
fi

# --- 4. Create DMG ---
echo "==> Creating DMG..."
if command -v create-dmg &>/dev/null; then
    create-dmg \
        --volname "MacDance" \
        --window-pos 200 120 \
        --window-size 600 400 \
        --icon-size 100 \
        --icon "MacDance.app" 175 190 \
        --app-drop-link 425 190 \
        --hide-extension "MacDance.app" \
        --no-internet-enable \
        "$DMG" "$APP"
else
    # Fallback: plain DMG without create-dmg
    hdiutil create -volname "MacDance" -srcfolder "$APP" \
        -ov -format UDZO "$DMG"
fi

rm -rf "$ARCHIVE" "$EXPORT_DIR" "$EXPORT_PLIST"

echo ""
echo "Done: $DMG"
echo "Size: $(du -h "$DMG" | cut -f1)"

#!/bin/bash
# Completely removes MacDance and all its data. No trace.
# Usage: ./uninstall.sh

set -euo pipefail

BUNDLE_ID="com.macdance.app"
APP="/Applications/MacDance.app"

echo "This will remove MacDance and all its data."
read -rp "Continue? [y/N] " confirm
[[ "$confirm" =~ ^[Yy]$ ]] || exit 0

# Kill if running
pkill -x MacDance 2>/dev/null || true

# App bundle
[ -d "$APP" ] && rm -rf "$APP" && echo "Removed $APP"

# Sandboxed container (all app data lives here)
rm -rf ~/Library/Containers/"$BUNDLE_ID"
rm -rf ~/Library/Group\ Containers/*macdance*

# Preferences & caches
defaults delete "$BUNDLE_ID" 2>/dev/null || true
rm -rf ~/Library/Caches/"$BUNDLE_ID"
rm -rf ~/Library/HTTPStorages/"$BUNDLE_ID"
rm -rf ~/Library/Saved\ Application\ State/"$BUNDLE_ID".savedState

# Privacy permissions
tccutil reset Camera "$BUNDLE_ID" 2>/dev/null || true
tccutil reset Microphone "$BUNDLE_ID" 2>/dev/null || true

echo "MacDance fully removed."

#!/bin/bash
# Archives the app (with its widget and watch app) and uploads it to App Store Connect.
# Usage: Scripts/release.sh [archive]   "archive" builds the .xcarchive only, without uploading.
# Needs Xcode signed in to the Apple Developer account (Settings > Accounts).
set -euo pipefail

cd "$(dirname "$0")/.."
archive="build/Snowoboarders.xcarchive"

xcodebuild archive \
    -project Snowoboarders.xcodeproj \
    -scheme Snowoboarders \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$archive" \
    -allowProvisioningUpdates

[ "${1:-}" = "archive" ] && { echo "Archive ready: $archive"; exit 0; }

xcodebuild -exportArchive \
    -archivePath "$archive" \
    -exportOptionsPlist ExportOptions.plist \
    -exportPath build/export \
    -allowProvisioningUpdates
echo "Uploaded. Watch for the processing email, then pick the build in App Store Connect."

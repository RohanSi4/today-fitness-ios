#!/bin/bash
# Build Today and install it on the connected iPhone.
#
# Exists because the install is three commands with one non-obvious failure
# mode: a phone that is plugged in but locked, or trusted-but-asleep, reports
# "unavailable" rather than "not found", and xcodebuild's error for that is a
# wall of provisioning output that does not mention the lock screen.
set -euo pipefail

cd "$(dirname "$0")/.."

DEVICE=$(xcrun devicectl list devices 2>/dev/null \
  | awk -F'  +' '/iPhone/ && (/available/ || /connected/) && !/unavailable/ {print $3; exit}')

if [ -z "$DEVICE" ]; then
  echo "No iPhone available." >&2
  echo >&2
  echo "  1. Plug the phone in, or put both on the same Wi-Fi." >&2
  echo "  2. Unlock it and leave it unlocked. A locked phone reads as" >&2
  echo "     'unavailable', not 'disconnected'." >&2
  echo "  3. Tap Trust if asked." >&2
  echo >&2
  echo "Current state:" >&2
  xcrun devicectl list devices >&2
  exit 1
fi

echo "Installing on $DEVICE"

DERIVED=$(mktemp -d)
trap 'rm -rf "$DERIVED"' EXIT

xcodebuild build \
  -project "Health Tracker.xcodeproj" \
  -scheme "Health Tracker" \
  -destination "id=$DEVICE" \
  -derivedDataPath "$DERIVED" \
  -allowProvisioningUpdates \
  -quiet

xcrun devicectl device install app \
  --device "$DEVICE" \
  "$DERIVED/Build/Products/Debug-iphoneos/Today.app"

echo
echo "Installed. First launch after a signing change can take a few seconds."
echo "If iOS refuses to open it, trust the certificate at:"
echo "  Settings > General > VPN & Device Management"

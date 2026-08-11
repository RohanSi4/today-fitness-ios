#!/bin/bash
# Build Today and install it on the connected iPhone.
#
# Exists because the install is three commands with one non-obvious failure
# mode: an unreachable phone reports "unavailable" rather than "not found", and
# xcodebuild's error for that is a wall of provisioning output that names
# neither the lock screen nor the network.
#
# "unavailable" has two causes that look identical here, and guessing the wrong
# one costs a while: the phone is locked or asleep, OR the wireless pairing has
# dropped. Unlocking does nothing for the second, so the message below leads
# with the cable - it fixes both. Note that `devicectl device info details`
# still answers for a device in this state, off a cached pairing record, so a
# successful info call is NOT evidence the device can be built to.
set -euo pipefail

cd "$(dirname "$0")/.."

DEVICE=$(xcrun devicectl list devices 2>/dev/null \
  | awk -F'  +' '/iPhone/ && (/available/ || /connected/) && !/unavailable/ {print $3; exit}')

if [ -z "$DEVICE" ]; then
  echo "No iPhone available." >&2
  echo >&2
  echo "  1. Plug the phone in with a cable. A dropped wireless pairing reads" >&2
  echo "     as 'unavailable', exactly like a locked phone does, and only the" >&2
  echo "     cable fixes both." >&2
  echo "  2. Unlock it and leave it unlocked." >&2
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

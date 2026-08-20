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

# ─── Provisioning expiry ──────────────────────────────────────────────────────
# A free Apple ID mints SEVEN-DAY profiles, and `-allowProvisioningUpdates`
# REUSES a still-valid one rather than refreshing it. On 2026-08-20 that put a
# build on the phone carrying a profile minted a week earlier with thirteen
# hours left on it. The app died overnight and the phone said "Today is no
# longer available", which looks nothing like a signing problem from the couch
# and sends you looking at privacy settings.
#
# Install time is the one moment the cable is guaranteed to be present, so it is
# the only sane moment to renew. Anything close to expiry is deleted here, which
# forces Xcode to mint a fresh seven days instead of inheriting a stale clock.
PROFILE_DIR="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
RENEW_WITHIN_DAYS=2

profile_expiry_epoch() {
  local raw
  raw=$(security cms -D -i "$1" 2>/dev/null | plutil -extract ExpirationDate raw - 2>/dev/null) || return 1
  # -u because the profile stamps UTC and the trailing Z in the format is a
  # LITERAL, not a zone. Without it `date` reads 17:34Z as 17:34 local and the
  # deadline printed below lands seven hours late — which is the one direction
  # that matters, since it would promise an afternoon the app has already lost.
  date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$raw" +%s 2>/dev/null
}

if [ -d "$PROFILE_DIR" ]; then
  cutoff=$(( $(date +%s) + RENEW_WITHIN_DAYS * 86400 ))
  for profile in "$PROFILE_DIR"/*.mobileprovision; do
    [ -e "$profile" ] || continue
    name=$(security cms -D -i "$profile" 2>/dev/null | plutil -extract Name raw - 2>/dev/null) || continue
    case "$name" in
      *Health-Tracker*) ;;
      *) continue ;;
    esac
    expiry=$(profile_expiry_epoch "$profile") || continue
    if [ "$expiry" -lt "$cutoff" ]; then
      echo "Renewing provisioning (expires $(date -r "$expiry" "+%b %d %H:%M")): $name"
      rm -f "$profile"
    fi
  done
fi

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

# Say the deadline out loud. On a free account the app stops launching the moment
# this passes, with no warning from the phone beyond "no longer available".
if [ -d "$PROFILE_DIR" ]; then
  for profile in "$PROFILE_DIR"/*.mobileprovision; do
    [ -e "$profile" ] || continue
    name=$(security cms -D -i "$profile" 2>/dev/null | plutil -extract Name raw - 2>/dev/null) || continue
    case "$name" in
      *Health-Tracker) ;;
      *) continue ;;
    esac
    expiry=$(profile_expiry_epoch "$profile") || continue
    echo
    echo "Signing valid until $(date -r "$expiry" "+%a %b %d, %-I:%M %p"). After that the app"
    echo "stops launching and reads 'no longer available' — rerun this script."
  done
fi

echo
echo "Installed. First launch after a signing change can take a few seconds."
echo "If iOS refuses to open it, trust the certificate at:"
echo "  Settings > General > VPN & Device Management"

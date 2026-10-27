#!/bin/bash
# Installs the latest NoSleep into /Applications and opens it.
#
#   curl -fsSL https://raw.githubusercontent.com/intuito-studio/nosleep/main/install.sh | bash
#
# A browser marks what it downloads as quarantined, and Gatekeeper then refuses
# an app without a paid Developer ID until it is allowed in System Settings.
# curl does not mark anything, so an app installed this way just opens.
set -euo pipefail

URL="${NOSLEEP_DMG_URL:-https://github.com/intuito-studio/nosleep/releases/latest/download/NoSleep.dmg}"
APPS="${NOSLEEP_APPDIR:-/Applications}"

WORK="$(mktemp -d)"
cleanup() {
	hdiutil detach -quiet "$WORK/volume" 2>/dev/null || true
	rm -rf "$WORK"
}
trap cleanup EXIT

echo "Downloading NoSleep…"
curl -fL --progress-bar "$URL" -o "$WORK/NoSleep.dmg"
hdiutil attach -quiet -nobrowse -readonly -mountpoint "$WORK/volume" "$WORK/NoSleep.dmg"

# Quit a running copy first; quitting switches sleep back on if it was holding it off.
if pgrep -xq NoSleep; then
	osascript -e 'tell application id "dev.intuito.nosleep" to quit' >/dev/null 2>&1 || pkill -x NoSleep || true
	sleep 1
fi

if [ ! -w "$APPS" ]; then
	echo "Can't write to $APPS. Run again as an admin user, or set NOSLEEP_APPDIR=~/Applications." >&2
	exit 1
fi
rm -rf "$APPS/NoSleep.app"
ditto "$WORK/volume/NoSleep.app" "$APPS/NoSleep.app"

echo "Installed $APPS/NoSleep.app"
open "$APPS/NoSleep.app"
echo "NoSleep is in the menu bar: a sleeping cat, or a tired one staring at a laptop while the Mac is kept awake. The first switch asks for your password once."

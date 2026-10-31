#!/bin/bash
# Assembles .build/NoSleep.app from the SPM binary and prints its path.
# No Xcode project needed — `swift build` stays the source of truth.
#
#   Scripts/bundle.sh [debug|release] [--universal]
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ARCH_FLAGS=()
if [ "${2:-}" = "--universal" ]; then
	# Release downloads have to run on Intel Macs too.
	ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi

swift build -c "$CONFIG" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --product NoSleep >&2
BIN_PATH="$(swift build -c "$CONFIG" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)"

APP="$ROOT/.build/NoSleep.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_PATH/NoSleep" "$APP/Contents/MacOS/NoSleep"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
# The MIT notice for the code ported from Mac Duo travels with the app.
cp "$ROOT/THIRD-PARTY-NOTICES.md" "$APP/Contents/Resources/"

# The Icon Composer bundle becomes Assets.car, which macOS 26 and later draws
# as Liquid Glass, plus AppIcon.icns, a flat render for macOS 14 and 15.
# actool ships with Xcode, not with the Command Line Tools.
PARTIAL_PLIST="$(mktemp)"
xcrun actool "$ROOT/Resources/AppIcon.icon" --compile "$APP/Contents/Resources" \
	--platform macosx --target-device mac --minimum-deployment-target 14.0 \
	--app-icon AppIcon --output-partial-info-plist "$PARTIAL_PLIST" >/dev/null
rm -f "$PARTIAL_PLIST"

VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist"

# Ad hoc on purpose, even where a development certificate exists: there is no
# Developer ID to notarise with, so every copy anyone downloads is ad hoc, and
# this build should be the same thing they run. Nothing here needs a TCC grant
# that would want a stable signature.
codesign --force --sign - "$APP" >&2

echo "$APP"

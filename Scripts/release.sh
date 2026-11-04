#!/bin/bash
# Builds the release: a universal NoSleep.app inside dist/NoSleep.dmg, the file
# install.sh and the in-app updater both download.
#
#   Scripts/release.sh
#
# The version comes from the VERSION file. Uploading is left to github.com:
# this machine does not use `gh`.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
VERSION="$(tr -d '[:space:]' < VERSION)"

APP="$(Scripts/bundle.sh release --universal)"
lipo -archs "$APP/Contents/MacOS/NoSleep" | grep -q x86_64 || { echo "not universal" >&2; exit 1; }

# The DMG holds the app and an Applications shortcut to drag it onto.
# It keeps one name across versions, so .../releases/latest/download/NoSleep.dmg
# always works for install.sh.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/NoSleep.app"
ln -s /Applications "$STAGE/Applications"
mkdir -p dist
rm -f dist/NoSleep.dmg
hdiutil create -quiet -volname "NoSleep" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov dist/NoSleep.dmg

SHA="$(shasum -a 256 dist/NoSleep.dmg | awk '{ print $1 }')"

cat <<EOF

NoSleep $VERSION
  dmg     $ROOT/dist/NoSleep.dmg
  sha256  $SHA

To publish:
  1. git tag v$VERSION && git push origin main v$VERSION
  2. On github.com, draft a release from tag v$VERSION, attach dist/NoSleep.dmg
     (keep the file name NoSleep.dmg) and publish it. Installed copies see it
     within a day.
EOF

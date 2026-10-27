#!/bin/bash
# Builds the downloadable release: a universal NoSleep.app inside dist/NoSleep.dmg,
# then points the Homebrew cask at it.
#
#   Scripts/release.sh
#
# The version comes from the VERSION file. Uploading is left to github.com:
# this machine does not use `gh`.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
VERSION="$(tr -d '[:space:]' < VERSION)"
TAP="${TAP:-$(cd "$ROOT/.." && pwd)/homebrew-tap}"
CASK="$TAP/Casks/nosleep.rb"

APP="$(Scripts/bundle.sh release --universal)"
lipo -archs "$APP/Contents/MacOS/NoSleep" | grep -q x86_64 || { echo "not universal" >&2; exit 1; }

# The DMG holds the app and an Applications shortcut to drag it onto.
# It keeps one name across versions, so .../releases/latest/download/NoSleep.dmg
# always works for install.sh; the cask pins the version through the tag instead.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/NoSleep.app"
ln -s /Applications "$STAGE/Applications"
mkdir -p dist
rm -f dist/NoSleep.dmg
hdiutil create -quiet -volname "NoSleep" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov dist/NoSleep.dmg

SHA="$(shasum -a 256 dist/NoSleep.dmg | awk '{ print $1 }')"

if [ -f "$CASK" ]; then
	sed -i '' -E \
		-e "s/^  version \".*\"/  version \"$VERSION\"/" \
		-e "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" \
		"$CASK"
	CASK_NOTE="updated $CASK"
else
	CASK_NOTE="no tap at $TAP, cask not updated (set TAP=/path/to/homebrew-tap)"
fi

cat <<EOF

NoSleep $VERSION
  dmg     $ROOT/dist/NoSleep.dmg
  sha256  $SHA
  cask    $CASK_NOTE

To publish:
  1. git tag v$VERSION && git push origin main v$VERSION
  2. On github.com, draft a release from tag v$VERSION and attach dist/NoSleep.dmg
     (keep the file name NoSleep.dmg).
  3. Commit and push the cask in the tap: cd $TAP && git commit -am "nosleep $VERSION" && git push
EOF

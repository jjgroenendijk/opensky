#!/bin/sh
# Copies the Release app to /Applications with the Release openskycli inside it, at
# Contents/MacOS/openskycli. A session can then drive the installed app with no build
# (docs/tools/agent-control.md#the-installed-cli). Adding the CLI breaks the bundle's
# seal, so the bundle is signed again with the identity Xcode signed it with.
#
# Usage: tools/install-app.sh APP CLI DEST
set -eu

if [ "$#" -ne 3 ]; then
    echo "[ERROR] usage: tools/install-app.sh APP CLI DEST" >&2
    exit 2
fi
app="$1"
cli="$2"
dest="$3"
[ -d "$app" ] || { echo "[ERROR] no app at $app" >&2; exit 2; }
[ -x "$cli" ] || { echo "[ERROR] no openskycli at $cli" >&2; exit 2; }

identity=$(codesign --display --verbose=2 "$app" 2>&1 | sed -n 's/^Authority=//p' | head -n 1)
[ -n "$identity" ] || { echo "[ERROR] $app is not signed with an identity" >&2; exit 1; }

rm -rf "$dest"
ditto "$app" "$dest"
ditto "$cli" "$dest/Contents/MacOS/openskycli"
codesign --force --sign "$identity" \
    --preserve-metadata=identifier,entitlements,requirements,flags,runtime "$dest"
codesign --verify --deep --strict "$dest"
echo "[ OK ] $dest updated, with Contents/MacOS/openskycli"

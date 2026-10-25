#!/bin/sh
# Builds the reference game: Wine from the gcenx Game Porting Toolkit cask, upgraded
# with Apple's GPTK 4 libraries, a Wine prefix with Windows Steam, and an APFS clone
# of the game. The OpenSky install is only read. See docs/tools/reference-game.md.
#
# Usage: reference/setup.sh PREFIX [GAME]
#   PREFIX  the folder for the Wine prefix, outside the repo and the game install.
#   GAME    the Skyrim SE install to copy. Default: the OpenSkyDataRoot setting.
# Each step is skipped when its result is already there, so a rerun continues.
set -eu

domain=nl.jjgroenendijk.opensky
app="/Applications/Game Porting Toolkit.app"
wine_dir="$app/Contents/Resources/wine"
wine="$wine_dir/bin/wine64"
marker="$wine_dir/lib/opensky-gptk-source"
steam_setup_url=https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe
repo="$(cd "$(dirname "$0")/.." && pwd)"

fail() {
    echo "[ERROR] $1" >&2
    exit 1
}

absolute() {
    case "$1" in
        /*) printf '%s\n' "$1" ;;
        *) printf '%s/%s\n' "$(pwd)" "$1" ;;
    esac
}

[ "$#" -ge 1 ] || fail "usage: reference/setup.sh PREFIX [GAME]"
prefix="$(absolute "$1")"
game="${2:-$(defaults read "$domain" OpenSkyDataRoot 2>/dev/null || true)}"
[ -n "$game" ] || fail "no game install; pass GAME or set the game folder in OpenSky"
game="${game%/}"
[ -f "$game/SkyrimSE.exe" ] || fail "not a Skyrim SE install: $game"

case "$prefix/" in
    "$repo"/* | "$game"/*) fail "the prefix must be outside the repo and the game install" ;;
esac

echo "[INFO] Step 1: Rosetta 2"
if ! arch -x86_64 /usr/bin/true 2>/dev/null; then
    fail "Rosetta 2 is missing. Run: softwareupdate --install-rosetta --agree-to-license"
fi

echo "[INFO] Step 2: the Game Porting Toolkit cask"
if [ ! -x "$wine" ]; then
    brew tap gcenx/wine
    brew install --cask gcenx/wine/game-porting-toolkit
    xattr -dr com.apple.quarantine "$app" 2>/dev/null || true
fi
[ -x "$wine" ] || fail "the cask did not install $wine"

echo "[INFO] Step 3: the GPTK 4 libraries"
gptk=""
for volume in /Volumes/Evaluation\ environment\ for\ Windows\ games*; do
    [ -d "$volume/redist/lib/wine" ] && gptk="$volume"
done
if [ -n "$gptk" ]; then
    # The image holds only the D3DMetal parts, so each folder starts from the cask's
    # copy, kept aside once, and the GPTK 4 files go over it.
    for part in external wine; do
        [ -d "$wine_dir/lib/$part.cask" ] || mv "$wine_dir/lib/$part" "$wine_dir/lib/$part.cask"
        rm -rf "${wine_dir:?}/lib/$part"
        ditto "$wine_dir/lib/$part.cask" "$wine_dir/lib/$part"
    done
    ditto "$gptk/redist/lib/" "$wine_dir/lib/"
    basename "$gptk" >"$marker"
elif [ ! -f "$marker" ]; then
    fail "download the Game Porting Toolkit 4 disk image from \
https://developer.apple.com/games/game-porting-toolkit/, open it, then run this again"
fi
echo "[INFO] Wine libraries from: $(cat "$marker")"

export WINEPREFIX="$prefix" WINEDEBUG=-all WINEMSYNC=1
echo "[INFO] Step 4: the Wine prefix in $prefix"
if [ ! -d "$prefix/drive_c" ]; then
    mkdir -p "$prefix"
    # Empty overrides skip the Wine Mono and Gecko prompts; the game needs neither.
    WINEDLLOVERRIDES="mscoree,mshtml=" "$wine" wineboot --init
    "$wine" winecfg -v win10
fi

echo "[INFO] Step 5: Windows Steam"
steam="$prefix/drive_c/Program Files (x86)/Steam"
if [ ! -f "$steam/steam.exe" ]; then
    curl -fL --retry 3 -o "$prefix/drive_c/SteamSetup.exe" "$steam_setup_url"
    "$wine" "$prefix/drive_c/SteamSetup.exe" /S
    rm -f "$prefix/drive_c/SteamSetup.exe"
fi
[ -f "$steam/steam.exe" ] || fail "the Steam installer did not finish: $steam"

echo "[INFO] Step 6: the reference copy of the game"
apps="$steam/steamapps"
if [ ! -f "$apps/common/Skyrim Special Edition/SkyrimSE.exe" ]; then
    mkdir -p "$apps/common"
    # A clone shares blocks with the original until one side changes; it reads only.
    cp -cR "$game" "$apps/common/" 2>/dev/null || cp -R "$game" "$apps/common/"
    cp "$game/../../appmanifest_489830.acf" "$apps/"
fi

defaults write "$domain" OpenSkyReferencePrefix "$prefix"
echo "[ OK ] Reference prefix ready: $prefix"
echo "[INFO] Next: make reference-game, log in to Steam once, then load a save."

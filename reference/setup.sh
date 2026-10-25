#!/bin/sh
# Builds the reference game in one folder: a private Wine 11.0 runtime with DXMT
# (Direct3D 11 on Metal), a Wine prefix with Windows Steam, and an APFS clone of
# the game. The OpenSky install is only read. See docs/tools/reference-game.md.
#
# Usage: reference/setup.sh PREFIX [GAME]
#   PREFIX  the folder for everything, outside the repo and the game install.
#   GAME    the Skyrim SE install to copy. Default: the OpenSkyDataRoot setting.
# Each step is skipped when its result is already there, so a rerun continues.
set -eu

domain=nl.jjgroenendijk.opensky
wine_url=https://github.com/Gcenx/macOS_Wine_builds/releases/download/11.0_1/wine-stable-11.0_1-osx64.tar.xz
wine_sha=b50dc50ec7f41d58b115a6b685d4d1315ba3c797bd3aa0f49213f2703cb82388
support_url=https://github.com/BCD1210/soju/releases/download/steam-support-v2/soju-steam-support-v2.tar.gz
support_sha=66cb0d95c2bf76d35b525b40e423e8b610e891bc61975078ae54661b51a2a86e
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

# download URL SHA256 FILE: fetches once and refuses a file with another hash.
download() {
    [ -f "$3" ] || curl -fL --retry 3 -o "$3.part" "$1"
    [ -f "$3" ] || mv "$3.part" "$3"
    echo "$2  $3" | shasum -a 256 -c --quiet || fail "hash mismatch: $3"
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

runtime="$prefix/opensky-runtime"
wine_dir="$runtime/wine"
lib="$wine_dir/lib/wine"
support="$runtime/steam-support"
mkdir -p "$runtime/downloads"

echo "[INFO] Step 1: Rosetta 2"
if ! arch -x86_64 /usr/bin/true 2>/dev/null; then
    fail "Rosetta 2 is missing. Run: softwareupdate --install-rosetta --agree-to-license"
fi

echo "[INFO] Step 2: Wine 11.0"
if [ ! -x "$wine_dir/bin/wine" ]; then
    download "$wine_url" "$wine_sha" "$runtime/downloads/wine-stable-11.0_1.tar.xz"
    rm -rf "$runtime/unpack"
    mkdir -p "$runtime/unpack"
    tar -xJf "$runtime/downloads/wine-stable-11.0_1.tar.xz" -C "$runtime/unpack"
    mv "$runtime/unpack/Wine Stable.app/Contents/Resources/wine" "$wine_dir"
    rm -rf "$runtime/unpack"
    xattr -dr com.apple.quarantine "$wine_dir" 2>/dev/null || true
fi
"$wine_dir/bin/wine" --version

echo "[INFO] Step 3: DXMT, the patched Mac driver, and the Steam web helper wrapper"
if [ ! -f "$support/SOURCES.txt" ]; then
    download "$support_url" "$support_sha" "$runtime/downloads/soju-steam-support-v2.tar.gz"
    mkdir -p "$support"
    tar -xzf "$runtime/downloads/soju-steam-support-v2.tar.gz" -C "$support"
fi
(cd "$support" && shasum -a 256 -c --quiet) <<'EOF' || fail "steam-support files changed"
539a8ad69f424f596e038ae3d4e7e4b1973c155f25dd7529578f73b424dc7b97  dxmt-x64/d3d11.dll
ec286d4323c2ac18fc405067526c93b07a9f5f1cef719ab15829e48b8bed79b9  dxmt-x64/dxgi.dll
53bc695d1408abd9067cf219a70e11c2f00d0c9c4c1065516de0fcfc81b95186  dxmt-x64/d3d10core.dll
799b0a094e6b0b9d1d967956ea8bff67792abdf24741a7a7035bf3e08febf7c5  dxmt-x64/winemetal.dll
6ae39285534a645ce4f33e55c07bcdc111847231bf42b005d260b1b2ae6913dc  dxmt-x64/winemetal.so
750784fccc7a0f6cd77a4bc4b372f81c09ba29bc62e79897b38240b142808547  winemac-patched.so
9302da71a4eed969dd4d679ba133c7735dafd08abcd491acddd6015dee579898  steamwebhelper-wrapper.exe
EOF
for dll in d3d11 dxgi d3d10core; do
    vanilla="$lib/x86_64-windows/$dll.dll.vanilla"
    [ -f "$vanilla" ] || cp "$lib/x86_64-windows/$dll.dll" "$vanilla"
done
[ -f "$lib/x86_64-unix/winemac.so.vanilla" ] ||
    cp "$lib/x86_64-unix/winemac.so" "$lib/x86_64-unix/winemac.so.vanilla"
for dll in d3d11 dxgi d3d10core winemetal; do
    cp "$support/dxmt-x64/$dll.dll" "$lib/x86_64-windows/"
done
cp "$support/dxmt-x64/winemetal.so" "$lib/x86_64-unix/"
cp "$support/winemac-patched.so" "$lib/x86_64-unix/winemac.so"

# winemenubuilder writes menu and desktop files into the macOS home folder.
export WINEPREFIX="$prefix" WINEDEBUG=-all WINEDLLOVERRIDES="winemenubuilder.exe=d"
wine() { "$wine_dir/bin/wine" "$@"; }

echo "[INFO] Step 4: the Wine prefix in $prefix"
if [ ! -d "$prefix/drive_c/windows" ]; then
    # Empty overrides skip the Wine Mono and Gecko prompts; the game needs neither.
    WINEDLLOVERRIDES="mscoree,mshtml=;winemenubuilder.exe=d" wine wineboot --init
    wine winecfg -v win10
fi
# Wine links Desktop, Documents, and the other user folders to the macOS home folder.
# Real folders keep the game's ini and saves, and Steam's shortcuts, in the prefix.
for link in "$prefix"/drive_c/users/*/*; do
    [ -L "$link" ] || continue
    rm "$link"
    mkdir "$link"
done
system32="$prefix/drive_c/windows/system32"
# DXMT needs a winemetal.dll in system32 to be found by name.
cp "$lib/x86_64-windows/winemetal.dll" "$system32/"
# Steam's own processes crash on DXMT, so they load Wine's own Direct3D from
# system32. Wine redirects a file with its builtin marker to the builtin (DXMT),
# so the copies get the marker changed.
for dll in d3d11 dxgi d3d10core; do
    cp "$lib/x86_64-windows/$dll.dll.vanilla" "$system32/$dll.dll"
    perl -pi -e 's/Wine builtin DLL/Xine builtin DLL/' "$system32/$dll.dll"
done
key='HKCU\Software\Wine'
wine reg add "$key\\DllOverrides" /v winemenubuilder.exe /t REG_SZ /d "" /f >/dev/null
for dll in d3d11 d3d10core dxgi winemetal; do
    wine reg add "$key\\DllOverrides" /v "$dll" /t REG_SZ /d builtin /f >/dev/null
done
for app in steam.exe steamwebhelper.exe steamwebhelper_real.exe steamservice.exe; do
    for dll in d3d11 d3d10core dxgi; do
        wine reg add "$key\\AppDefaults\\$app\\DllOverrides" /v "$dll" /t REG_SZ /d native /f >/dev/null
    done
    wine reg add "$key\\AppDefaults\\$app\\DllOverrides" /v winemetal /t REG_SZ /d disabled /f >/dev/null
done
# Wine 11.0 probes each audio device format by format in Steam's main loop;
# with microphones or virtual devices that stalls the client before login.
wine reg add "$key\\AppDefaults\\steam.exe\\DllOverrides" /v winecoreaudio.drv \
    /t REG_SZ /d disabled /f >/dev/null

echo "[INFO] Step 5: Windows Steam"
steam="$prefix/drive_c/Program Files (x86)/Steam"
if [ ! -f "$steam/steam.exe" ]; then
    curl -fL --retry 3 -o "$prefix/drive_c/SteamSetup.exe" "$steam_setup_url"
    wine "$prefix/drive_c/SteamSetup.exe" /S
    rm -f "$prefix/drive_c/SteamSetup.exe"
fi
[ -f "$steam/steam.exe" ] || fail "the Steam installer did not finish: $steam"
# The first start downloads and updates the Steam client. Steam starts its browser
# helper only once the update is done; the launcher then swaps the helper for the
# wrapper before each later start, so a later start does not update again.
if [ ! -f "$steam/steamui.dll" ]; then
    echo "[INFO] Downloading the Steam client; this takes a few minutes"
    WINEDLLOVERRIDES="bcrypt=b;ncrypt=b;gameoverlayrenderer,gameoverlayrenderer64=d;winemenubuilder.exe=d" \
        wine 'C:\Program Files (x86)\Steam\steam.exe' -no-cef-sandbox -cef-single-process \
        >"$runtime/steam-bootstrap.log" 2>&1 &
    waited=0
    until pgrep -f 'cef.win64.steamwebhelper.exe' >/dev/null; do
        [ "$waited" -lt 900 ] || fail "Steam did not download its client in 15 minutes"
        sleep 5
        waited=$((waited + 5))
    done
    "$wine_dir/bin/wineserver" -k
fi

echo "[INFO] Step 6: the reference copy of the game"
apps="$steam/steamapps"
if [ ! -f "$apps/common/Skyrim Special Edition/SkyrimSE.exe" ]; then
    mkdir -p "$apps/common"
    # A clone shares blocks with the original until one side changes; it reads only.
    cp -cR "$game" "$apps/common/" 2>/dev/null || cp -R "$game" "$apps/common/"
    cp "$game/../../appmanifest_489830.acf" "$apps/"
fi
"$wine_dir/bin/wineserver" -w

defaults write "$domain" OpenSkyReferencePrefix "$prefix"
echo "[ OK ] Reference prefix ready: $prefix"
echo "[INFO] Next: make reference-game, log in to Steam once, then load a save."

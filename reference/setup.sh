#!/bin/sh
# Builds the reference game in one folder: a private Wine 11.0 runtime, DXVK
# (Direct3D 11 on Vulkan, which Wine runs on Metal through MoltenVK), GStreamer for
# the game's audio, a Wine prefix with Windows Steam, and an APFS clone of the game. The OpenSky install is only read. See docs/tools/reference-game.md.
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
dxvk_url=https://github.com/Gcenx/DXVK-macOS/releases/download/v1.10.3-20230507-repack/dxvk-macOS-async-v1.10.3-20230507-repack.tar.gz
dxvk_sha=acd1520ad105d8ef124a09c8e11a259a5dc8bdc565ad18e0e52693f9807b2477
gst_version=1.28.8
gst_url=https://gstreamer.freedesktop.org/data/pkg/osx/$gst_version/gstreamer-1.0-$gst_version-universal.pkg
gst_sha=d371ab04a7632713626836c2fc234e863cc98484c74c473eba99b0fbd9b3a3fe
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

echo "[INFO] Step 3: the Steam web helper wrapper, DXVK, and GStreamer"
if [ ! -f "$support/SOURCES.txt" ]; then
    download "$support_url" "$support_sha" "$runtime/downloads/soju-steam-support-v2.tar.gz"
    mkdir -p "$support"
    tar -xzf "$runtime/downloads/soju-steam-support-v2.tar.gz" -C "$support"
fi
dxvk="$runtime/dxvk"
if [ ! -d "$dxvk/x64" ]; then
    download "$dxvk_url" "$dxvk_sha" "$runtime/downloads/dxvk-macOS-1.10.3.tar.gz"
    mkdir -p "$dxvk"
    tar -xzf "$runtime/downloads/dxvk-macOS-1.10.3.tar.gz" -C "$dxvk" --strip-components 1
fi
(cd "$runtime" && shasum -a 256 -c --quiet) <<'EOF' || fail "downloaded files changed"
9302da71a4eed969dd4d679ba133c7735dafd08abcd491acddd6015dee579898  steam-support/steamwebhelper-wrapper.exe
0ff0b0835dde29556bd01dfce7b1ae348d7f229cb1e1a37cc71ea1a028beeca4  dxvk/x64/d3d11.dll
0fa08bba860c63e3abeeabfc96d0e7aa327411a975f8f23d2dc63594ef5f796e  dxvk/x64/d3d10core.dll
EOF
# Wine decodes the game's xWMA audio through GStreamer, which it otherwise looks for
# in /Library/Frameworks. The package is unpacked here instead of installed.
gst="$runtime/gstreamer"
if [ ! -x "$gst/libexec/gstreamer-1.0/gst-plugin-scanner" ]; then
    download "$gst_url" "$gst_sha" "$runtime/downloads/gstreamer-$gst_version.pkg"
    rm -rf "$runtime/gst-unpack" "$gst"
    pkgutil --expand-full "$runtime/downloads/gstreamer-$gst_version.pkg" "$runtime/gst-unpack"
    mkdir -p "$gst"
    for part in base-system-1.0 base-crypto gstreamer-1.0-core gstreamer-1.0-system \
        gstreamer-1.0-playback gstreamer-1.0-codecs gstreamer-1.0-libav; do
        cp -R "$runtime/gst-unpack/$part-$gst_version-universal.pkg/Payload/" "$gst/"
    done
    rm -rf "$runtime/gst-unpack"
fi

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
key='HKCU\Software\Wine'
wine reg add "$key\\DllOverrides" /v winemenubuilder.exe /t REG_SZ /d "" /f >/dev/null
# DXVK draws the game; Steam keeps Wine's own Direct3D.
for dll in d3d11 d3d10core; do
    wine reg add "$key\\AppDefaults\\SkyrimSE.exe\\DllOverrides" /v "$dll" /t REG_SZ /d native /f >/dev/null
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
# The game loads a native DLL from its own folder first.
cp "$dxvk/x64/d3d11.dll" "$dxvk/x64/d3d10core.dll" "$apps/common/Skyrim Special Edition/"
"$wine_dir/bin/wineserver" -w

defaults write "$domain" OpenSkyReferencePrefix "$prefix"
echo "[ OK ] Reference prefix ready: $prefix"
echo "[INFO] Next: make reference-game, log in to Steam once, then load a save."

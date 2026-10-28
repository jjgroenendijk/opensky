#!/bin/sh
# Installs SKSE and the Address Library into the reference copy of the game, then builds
# the OpenSkyBridge plugin on this Mac and installs it there too. Homebrew holds the
# compiler and linker; xwin writes the Windows SDK into the prefix. Nothing lands in the
# repo (docs/tools/reference-game.md#the-bridge-plugin).
#
# Usage: [SKSE=<archive>] [ADDRESS_LIBRARY=<archive>] reference/bridge/build.sh PREFIX
#   SKSE             the SKSE64 archive for the game's version, downloaded from Nexus.
#   ADDRESS_LIBRARY  the Address Library "All in one (Anniversary Edition)" archive.
# Each part is skipped when it is already installed, so a rerun only rebuilds the plugin.
set -eu

fail() {
    echo "[ERROR] $1" >&2
    exit 1
}

[ "$#" -eq 1 ] || fail "usage: reference/bridge/build.sh PREFIX"
prefix="${1%/}"
source="$(cd "$(dirname "$0")" && pwd)"
runtime="$prefix/opensky-runtime"
game="$prefix/drive_c/Program Files (x86)/Steam/steamapps/common/Skyrim Special Edition"
plugins="$game/Data/SKSE/Plugins"
[ -f "$game/SkyrimSE.exe" ] || fail "no reference copy of the game in $prefix; run make reference-setup"
mkdir -p "$plugins"

# unpack ARCHIVE: a fresh folder with the archive's files; macOS tar reads 7z and zip.
unpack() {
    [ -f "$1" ] || fail "no such archive: $1"
    rm -rf "$runtime/unpack"
    mkdir -p "$runtime/unpack"
    tar -xf "$1" -C "$runtime/unpack"
}

echo "[INFO] Step 1: SKSE"
if [ ! -f "$game/skse64_loader.exe" ]; then
    [ -n "${SKSE:-}" ] || fail "SKSE is not installed. Download the build for the game's version \
from https://www.nexusmods.com/skyrimspecialedition/mods/30379 and pass SKSE=<archive>"
    unpack "$SKSE"
    # Only the loader and its DLL: SKSE's scripts would replace the game's own.
    find "$runtime/unpack" -maxdepth 2 -type f \( -name 'skse64_*.exe' -o -name 'skse64_*.dll' \) \
        -exec cp {} "$game/" \;
    rm -rf "$runtime/unpack"
    [ -f "$game/skse64_loader.exe" ] || fail "no skse64_loader.exe in $SKSE"
fi

echo "[INFO] Step 2: the Address Library"
if ! ls "$plugins"/versionlib-*.bin >/dev/null 2>&1; then
    [ -n "${ADDRESS_LIBRARY:-}" ] || fail "the Address Library is not installed. Download \
\"All in one (Anniversary Edition)\" from https://www.nexusmods.com/skyrimspecialedition/mods/32444 \
and pass ADDRESS_LIBRARY=<archive>"
    unpack "$ADDRESS_LIBRARY"
    find "$runtime/unpack" -type f -name 'versionlib-*.bin' -exec cp {} "$plugins/" \;
    rm -rf "$runtime/unpack"
    ls "$plugins"/versionlib-*.bin >/dev/null 2>&1 || fail "no versionlib-*.bin in $ADDRESS_LIBRARY"
fi

echo "[INFO] Step 3: the compiler and the Windows SDK"
# The prebuilt CommonLibSSE-NG library needs clang-cl 22.1.
for formula in llvm@22 lld@22 xwin cmake ninja; do
    brew list --versions "$formula" >/dev/null 2>&1 || brew install "$formula"
done
llvm="$(brew --prefix llvm@22)"
lld="$(brew --prefix lld@22)"
sysroot="$runtime/xwin"
# Visual Studio 2026 (manifest 18): the library calls STL helpers older toolsets lack.
if [ ! -f "$sysroot/manifest-18" ]; then
    rm -rf "$sysroot"
    echo "[INFO] Downloading the Windows SDK and MSVC headers with xwin."
    echo "[INFO] This accepts Microsoft's licence: https://go.microsoft.com/fwlink/?LinkId=2086102"
    xwin --accept-license --arch x86_64 --manifest-version 18 --http-retry 10 \
        --cache-dir "$runtime/xwin-cache" \
        splat --output "$sysroot" --use-winsysroot-style --preserve-ms-arch-notation
    rm -rf "$runtime/xwin-cache"
    touch "$sysroot/manifest-18"
fi

echo "[INFO] Step 4: the bridge plugin"
build="$runtime/bridge-build"
cmake -S "$source" -B "$build" -G Ninja -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_TOOLCHAIN_FILE="$source/cmake/macos-clangcl.cmake" \
    -DLLVM_PREFIX="$llvm" -DLLD_PREFIX="$lld" -DXWIN_SYSROOT="$sysroot" >/dev/null
cmake --build "$build"
cp "$build/OpenSkyBridge.dll" "$plugins/"
echo "[ OK ] Installed $plugins/OpenSkyBridge.dll"
echo "[INFO] make reference-game now starts the game through SKSE with the bridge."

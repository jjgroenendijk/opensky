#!/bin/sh
# OpenSky vendored ffmpeg: a minimal, decode-only, LGPL-only build of libavutil,
# libavcodec and libswresample, used by opensky/Audio to turn WMAv2 payloads into PCM.
#
# Homebrew's ffmpeg is deliberately not used: it is configured --enable-gpl
# --enable-version3, which would relicense a redistributed OpenSky, and it drags in
# roughly fifteen third-party dylibs at absolute paths. See docs/decisions/ffmpeg-audio.md.
#
# Invoked by `make bootstrap` and by `make ffmpeg`. Idempotent: a matching build stamp
# short-circuits the whole script. Set OPENSKY_FFMPEG_FORCE=1 to rebuild anyway.
#
# The build always lands in the shared `.vendor` of the main checkout, whichever worktree
# it was started from, because the result is identical for all of them. Linked worktrees
# reach it through the symlink tools/ffmpeg/link-vendor.sh creates.
set -eu

FFMPEG_VERSION=8.1.2
# Cross-checked against the sha256 Homebrew pins for the same tarball, since ffmpeg.org
# publishes only detached GPG signatures and no checksum file.
FFMPEG_SHA256=464beb5e7bf0c311e68b45ae2f04e9cc2af88851abb4082231742a74d97b524c
# Bump when the configure flags below change, so existing prefixes rebuild.
FLAGS_REVISION=1

ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"

# Link this worktree at the shared prefix (a no-op in the main checkout) before deciding
# where to build, so both this script and Xcode see the same directory.
"$ROOT/tools/ffmpeg/link-vendor.sh"

# In the main checkout this is $ROOT; in a linked worktree it is the main checkout.
SHARED=$(cd "$(dirname "$(git rev-parse --git-common-dir)")" && pwd)

PREFIX="$SHARED/.vendor/ffmpeg"
SRC_DIR="$SHARED/.vendor/src"
BUILD_DIR="$SRC_DIR/ffmpeg-$FFMPEG_VERSION"
TARBALL="$SRC_DIR/ffmpeg-$FFMPEG_VERSION.tar.xz"
STAMP="$PREFIX/opensky-build-stamp"
LOG="$ROOT/logs/vendor-ffmpeg.log"
WANT_STAMP="ffmpeg $FFMPEG_VERSION flags $FLAGS_REVISION"

fail() {
  echo "[ERROR] $1" >&2
  echo "        full build log: $LOG" >&2
  exit 1
}

if [ "${OPENSKY_FFMPEG_FORCE:-0}" != "1" ] && [ -f "$STAMP" ] &&
  [ "$(cat "$STAMP")" = "$WANT_STAMP" ]; then
  echo "  [ OK ] ffmpeg $FFMPEG_VERSION (vendored, decode-only LGPL)"
  exit 0
fi

mkdir -p "$SRC_DIR" "$ROOT/logs"
: >"$LOG"

echo "  [INFO] building vendored ffmpeg $FFMPEG_VERSION (decode-only, LGPL) -> $PREFIX"

if [ ! -f "$TARBALL" ]; then
  echo "  [INFO] downloading $FFMPEG_VERSION source tarball"
  curl -fsSL --retry 3 -o "$TARBALL.part" \
    "https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VERSION.tar.xz" >>"$LOG" 2>&1 ||
    fail "download failed"
  mv "$TARBALL.part" "$TARBALL"
fi

got=$(shasum -a 256 "$TARBALL" | cut -d' ' -f1)
if [ "$got" != "$FFMPEG_SHA256" ]; then
  rm -f "$TARBALL"
  fail "tarball checksum mismatch: expected $FFMPEG_SHA256, got $got"
fi

rm -rf "$BUILD_DIR" "$PREFIX"
tar -xf "$TARBALL" -C "$SRC_DIR" >>"$LOG" 2>&1 || fail "extract failed"

# --disable-everything turns off every component, then wmav2 is switched back on by hand.
# --disable-autodetect stops configure from picking up anything installed on this machine,
# which is what keeps the result free of third-party (and possibly GPL) code.
# --install-name-dir=@rpath makes the dylibs relocatable so they can be embedded in
# opensky.app without any install_name_tool rewriting.
(
  cd "$BUILD_DIR" &&
    ./configure \
      --prefix="$PREFIX" \
      --disable-everything \
      --disable-gpl \
      --disable-nonfree \
      --disable-autodetect \
      --disable-programs \
      --disable-doc \
      --disable-network \
      --disable-avdevice \
      --disable-avfilter \
      --disable-avformat \
      --disable-swscale \
      --disable-static \
      --enable-shared \
      --enable-decoder=wmav2 \
      --install-name-dir=@rpath \
      --extra-cflags=-mmacosx-version-min=26.0 \
      --extra-ldflags=-mmacosx-version-min=26.0
) >>"$LOG" 2>&1 || fail "configure failed"

(cd "$BUILD_DIR" && make -j"$(sysctl -n hw.ncpu)" install) >>"$LOG" 2>&1 ||
  fail "build failed"

# Licensing is a correctness gate here, not paperwork: linking a GPL-configured libavcodec
# would silently relicense OpenSky. Ask the built library itself rather than trusting the
# flags above.
CHECK_SRC="$SRC_DIR/opensky-ffmpeg-check.c"
cat >"$CHECK_SRC" <<'CHECK'
#include <libavcodec/avcodec.h>
#include <libavutil/avutil.h>
#include <stdio.h>

int main(void) {
  printf("license: %s\n", avutil_license());
  printf("configuration: %s\n", avcodec_configuration());
  printf("wmav2: %s\n",
         avcodec_find_decoder(AV_CODEC_ID_WMAV2) ? "present" : "missing");
  return 0;
}
CHECK

clang "$CHECK_SRC" -I"$PREFIX/include" -L"$PREFIX/lib" -lavutil -lavcodec \
  -Wl,-rpath,"$PREFIX/lib" -o "$SRC_DIR/opensky-ffmpeg-check" >>"$LOG" 2>&1 ||
  fail "license-check probe failed to build"

report=$("$SRC_DIR/opensky-ffmpeg-check") || fail "license-check probe failed to run"
printf '%s\n' "$report" >>"$LOG"

echo "$report" | grep -q '^license: LGPL version 2.1 or later' ||
  fail "vendored ffmpeg is not LGPL 2.1: $(echo "$report" | grep '^license:')"
echo "$report" | grep -q '^wmav2: present' || fail "wmav2 decoder missing from the build"
echo "$report" | grep -q -- '--disable-gpl' || fail "--disable-gpl absent from configuration"
echo "$report" | grep -q -- '--disable-nonfree' ||
  fail "--disable-nonfree absent from configuration"
if echo "$report" | grep -qE -- '--enable-(gpl|nonfree|version3|lib[a-z0-9]+)'; then
  fail "configuration enables GPL, nonfree or a third-party library"
fi

# Every dependency must be either a sibling dylib (@rpath) or an OS library, so the three
# copies embedded in opensky.app are the whole closure.
for lib in "$PREFIX"/lib/libavutil.dylib "$PREFIX"/lib/libavcodec.dylib \
  "$PREFIX"/lib/libswresample.dylib; do
  [ -f "$lib" ] || fail "expected library missing: $lib"
  stray=$(otool -L "$lib" | tail -n +2 | awk '{print $1}' |
    grep -vE '^(@rpath/|/usr/lib/|/System/)' || true)
  [ -z "$stray" ] || fail "$(basename "$lib") links non-system libraries: $stray"
done

# Xcode's user-script sandbox grants a build phase read and write access only to the exact
# paths it declares, and the dylib version numbers are this script's business rather than
# the project file's. Emit both sides as .xcfilelists for the "Embed vendored ffmpeg" phase:
# resolved sources to read, and the install names they are embedded under to write.
: >"$PREFIX/embed-inputs.xcfilelist"
: >"$PREFIX/embed-outputs.xcfilelist"
for name in libavutil libavcodec libswresample; do
  resolved=$(cd "$PREFIX/lib" && readlink "$name.dylib" || echo "$name.dylib")
  echo "$PREFIX/lib/$resolved" >>"$PREFIX/embed-inputs.xcfilelist"
  soname=$(basename "$(otool -D "$PREFIX/lib/$name.dylib" | tail -1)")
  # Xcode expands build settings inside a file list, so these stay literal here.
  embedded="\$(BUILT_PRODUCTS_DIR)/\$(FRAMEWORKS_FOLDER_PATH)/$soname"
  # codesign rewrites through a sibling .cstemp file, which the sandbox must also allow.
  printf '%s\n%s.cstemp\n' "$embedded" "$embedded" >>"$PREFIX/embed-outputs.xcfilelist"
done

# The extracted source tree has done its job; drop it so .vendor stays small and repo-wide
# linters never see upstream files. The verified tarball stays for a cheap rebuild.
rm -rf "$BUILD_DIR"

echo "$WANT_STAMP" >"$STAMP"
echo "  [ OK ] ffmpeg $FFMPEG_VERSION vendored (LGPL 2.1, decoders: wmav2)"

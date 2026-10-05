#!/bin/sh
# OpenSky vendored astcenc: ARM's ASTC encoder (Apache-2.0) as a static NEON library,
# used by Sources/CASTCEncoder to encode textures at every ASTC block size and effort
# level. See docs/decisions/astcenc.md.
#
# Invoked by `make bootstrap` and by `make astcenc`. Idempotent: a matching build stamp
# short-circuits the whole script. Set OPENSKY_ASTCENC_FORCE=1 to rebuild anyway.
#
# Like ffmpeg, the build lands in the shared `.vendor` of the main checkout, and linked
# worktrees reach it through tools/link-shared.sh.
set -eu

ASTCENC_VERSION=5.7.0
# sha256 of the GitHub source tarball for the tag, checked when it was pinned.
ASTCENC_SHA256=7c1b28ece59c9c2737e297123a9910c1c548676c7aed87a09d5734e2fa7bdaf0
# Bump when the CMake flags below change, so existing prefixes rebuild.
FLAGS_REVISION=1

ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
"$ROOT/tools/link-shared.sh"
SHARED=$(cd "$(dirname "$(git rev-parse --git-common-dir)")" && pwd)

PREFIX="$SHARED/.vendor/astcenc"
SRC_DIR="$SHARED/.vendor/src"
BUILD_DIR="$SRC_DIR/astc-encoder-$ASTCENC_VERSION"
TARBALL="$SRC_DIR/astc-encoder-$ASTCENC_VERSION.tar.gz"
STAMP="$PREFIX/opensky-build-stamp"
LOG=""
WANT_STAMP="astcenc $ASTCENC_VERSION flags $FLAGS_REVISION"

fail() {
  echo "[ERROR] $1" >&2
  echo "        full build log: $LOG" >&2
  exit 1
}

if [ "${OPENSKY_ASTCENC_FORCE:-0}" != "1" ] && [ -f "$STAMP" ] &&
  [ "$(cat "$STAMP")" = "$WANT_STAMP" ]; then
  echo "  [ OK ] astcenc $ASTCENC_VERSION (vendored, static NEON)"
  exit 0
fi

command -v cmake >/dev/null 2>&1 || {
  echo "[ERROR] cmake not found; run make bootstrap" >&2
  exit 1
}

mkdir -p "$SRC_DIR"
RUN_DIR="$("$ROOT/tools/run-dir.sh" vendor-astcenc)"
LOG="$RUN_DIR/vendor-astcenc.log"
: >"$LOG"
echo "  [INFO] run directory: $RUN_DIR"
echo "  [INFO] building vendored astcenc $ASTCENC_VERSION -> $PREFIX"

if [ ! -f "$TARBALL" ]; then
  curl -fsSL --retry 3 -o "$TARBALL.part" \
    "https://github.com/ARM-software/astc-encoder/archive/refs/tags/$ASTCENC_VERSION.tar.gz" \
    >>"$LOG" 2>&1 || fail "download failed"
  mv "$TARBALL.part" "$TARBALL"
fi

got=$(shasum -a 256 "$TARBALL" | cut -d' ' -f1)
if [ "$got" != "$ASTCENC_SHA256" ]; then
  rm -f "$TARBALL"
  fail "tarball checksum mismatch: expected $ASTCENC_SHA256, got $got"
fi

rm -rf "$BUILD_DIR" "$PREFIX"
tar -xzf "$TARBALL" -C "$SRC_DIR" >>"$LOG" 2>&1 || fail "extract failed"

# Only the core library: no command-line tool, no universal build, Apple Silicon only.
cmake -S "$BUILD_DIR" -B "$BUILD_DIR/build" \
  -DCMAKE_BUILD_TYPE=Release \
  -DASTCENC_ISA_NEON=ON \
  -DASTCENC_CLI=OFF \
  -DASTCENC_UNIVERSAL_BUILD=OFF \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=26.0 >>"$LOG" 2>&1 || fail "configure failed"
cmake --build "$BUILD_DIR/build" -j"$(sysctl -n hw.ncpu)" >>"$LOG" 2>&1 || fail "build failed"

mkdir -p "$PREFIX/lib" "$PREFIX/include"
cp "$BUILD_DIR/build/Source/libastcenc-neon-static.a" "$PREFIX/lib/libastcenc.a" ||
  fail "static library missing from the build"
cp "$BUILD_DIR/Source/astcenc.h" "$PREFIX/include/" || fail "header missing"
cp "$BUILD_DIR/LICENSE.txt" "$PREFIX/LICENSE.txt"

# The source tree has done its job; the verified tarball stays for a cheap rebuild.
rm -rf "$BUILD_DIR"

echo "$WANT_STAMP" >"$STAMP"
echo "  [ OK ] astcenc $ASTCENC_VERSION vendored (Apache-2.0, static NEON)"

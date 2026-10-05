#!/bin/sh
# OpenSky one-shot dev bootstrap: install tools. Idempotent.
# Invoked by `make bootstrap`.
set -eu

cd "$(git rev-parse --show-toplevel)"

echo "[INFO] Checking toolchain..."
if ! command -v brew >/dev/null 2>&1; then
  echo "[FAIL] Homebrew required: https://brew.sh" >&2
  exit 1
fi

# Formatters + linters are mandatory (AGENTS.md "Code quality"). jscpd and
# periphery are the code-health gates (docs/decisions/code-health-automation.md).
for tool in swiftformat swiftlint markdownlint-cli2 shellcheck actionlint jscpd periphery; do
  if command -v "$tool" >/dev/null 2>&1; then
    echo "  [ OK ] $tool"
  else
    echo "  [INFO] installing $tool"
    brew install "$tool"
  fi
done

# librsvg: rsvg-convert renders the AppIcon set from the SVG logo (make icon).
if command -v rsvg-convert >/dev/null 2>&1; then
  echo "  [ OK ] rsvg-convert"
else
  echo "  [INFO] installing librsvg"
  brew install librsvg
fi

# Audio decode needs a decode-only, LGPL-only ffmpeg that we build ourselves; Homebrew's
# is GPL-configured (docs/decisions/ffmpeg-audio.md).
./tools/vendor-ffmpeg.sh

# ASTC texture encoding uses ARM's astcenc, built from a pinned source tarball with cmake
# (docs/decisions/astcenc.md).
if command -v cmake >/dev/null 2>&1; then
  echo "  [ OK ] cmake"
else
  echo "  [INFO] installing cmake"
  brew install cmake
fi
./tools/vendor-astcenc.sh

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "  [WARN] xcodebuild not found — install Xcode from the App Store." >&2
else
  # Metal shader compilation needs the Metal Toolchain component (Xcode 26+).
  if xcodebuild -showComponent MetalToolchain 2>/dev/null | grep -q 'Status: installed'; then
    echo "  [ OK ] Metal Toolchain"
  else
    echo "  [INFO] downloading Metal Toolchain (one-time, large)"
    xcodebuild -downloadComponent MetalToolchain
  fi
fi

echo "[ OK ] Bootstrap complete. Try: make check"

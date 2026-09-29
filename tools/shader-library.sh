#!/bin/sh
# Compile Sources/Shaders/Shaders.metal into one .metallib for the package test
# targets. The app and openskycli compile the same file into the default.metallib
# of their own bundle. A package test has no such bundle, and `swift test` does not
# compile Shaders.metal, so a test fixture loads this file instead. It finds the
# file through OPENSKY_SHADER_LIBRARY: the Makefile exports it for `swift test`,
# and Config/TestPlans/UnitTests.xctestplan sets it for xcodebuild.
#
# The flags follow the Metal settings in Config/Build/*.xcconfig: the macOS
# deployment target, fast math, warnings as errors, and ShaderTypes.h on the
# include path. Change both together.
#
# Usage: tools/shader-library.sh OUTPUT
set -eu

if [ "$#" -ne 1 ] || [ -z "$1" ]; then
    echo "[ERROR] usage: tools/shader-library.sh OUTPUT.metallib" >&2
    exit 2
fi
output="$1"
root="$(cd "$(dirname "$0")/.." && pwd)"

mkdir -p "$(dirname "$output")"
# Write to a temporary name first, so a failed compile never leaves a file that
# looks current to make.
xcrun -sdk macosx metal \
    -mmacosx-version-min=26.0 \
    -fmetal-math-mode=fast \
    -Werror \
    -I "$root/Sources/OpenSkyShaderTypes" \
    -o "$output.tmp" \
    "$root/Sources/Shaders/Shaders.metal"
mv "$output.tmp" "$output"
echo "[ OK ] shader library: $output"

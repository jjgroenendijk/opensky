#!/bin/sh
# Writes a fake of each OpenSkySessionInterface port a test names into OpenSkySessionTesting, or
# into the folder given, then formats it. The generator in tools/fake-gen/ is built once per
# source hash with the SwiftSyntax that ships in Xcode.
# Usage: tools/fakes.sh [output folder]
set -eu
tools="$(cd "$(dirname "$0")" && pwd)"
root="$(git rev-parse --show-toplevel)"
output="${1:-$root/src/Tests/OpenSkySessionTesting}"
shared="$(dirname "$(git -C "$tools" rev-parse --path-format=absolute --git-common-dir)")"
toolchain="$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/host"
hash="$( { swiftc --version 2>&1; cat "$tools"/fake-gen/*.swift; } | shasum | cut -c1-16)"
generator="$shared/.cache/fake-gen/$hash/fake-gen"
if [ ! -x "$generator" ]; then
    mkdir -p "$(dirname "$generator")"
    swiftc -O -module-name FakeGen "$tools"/fake-gen/*.swift -o "$generator.tmp" \
        -I "$toolchain" -L "$toolchain" -lSwiftSyntax -lSwiftParser \
        -Xlinker -rpath -Xlinker "$toolchain"
    mv "$generator.tmp" "$generator"
fi
"$generator" "$root" "$output"
swiftformat --quiet --config "$tools/format/.swiftformat" "$output"

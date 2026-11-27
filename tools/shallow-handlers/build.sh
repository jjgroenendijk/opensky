#!/bin/sh
# Builds tools/shallow-handlers once per source hash with the SwiftSyntax that ships in
# Xcode, as tools/lint/syntax-rules.sh builds its checker, then runs it.
# Usage: tools/shallow-handlers/build.sh <repo> <out>, or --self-check.
set -eu
source_dir="$(cd "$(dirname "$0")" && pwd)"
shared="$(dirname "$(git -C "$source_dir" rev-parse --path-format=absolute --git-common-dir)")"
toolchain="$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/host"
hash="$( { swiftc --version 2>&1; cat "$source_dir"/*.swift; } | shasum | cut -c1-16)"
tool="$shared/.cache/shallow-handlers/$hash/shallow-handlers"
if [ ! -x "$tool" ]; then
    mkdir -p "$(dirname "$tool")"
    swiftc -O -module-name ShallowHandlers "$source_dir"/*.swift -o "$tool.$$" \
        -I "$toolchain" -L "$toolchain" -lSwiftSyntax -lSwiftParser \
        -Xlinker -rpath -Xlinker "$toolchain"
    mv "$tool.$$" "$tool"
fi
exec "$tool" "$@"

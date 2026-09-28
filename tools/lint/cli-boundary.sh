#!/bin/sh
# CLI target-boundary lint (issues #109, #336). Target membership follows the
# folder split under Sources/: OpenSky/ builds only into the app, and every other
# folder is a package module or shader source that OpenSkyCLI also links. So an
# AppKit, Cocoa, or SwiftUI import anywhere outside Sources/OpenSky/ enters the CLI
# build and breaks it. This asserts there are none — catches the break at commit
# time, no CLI build.
set -eu

cd "$(git rev-parse --show-toplevel)"

engine_dirs="$(find Sources -mindepth 1 -maxdepth 1 -type d ! -name OpenSky | sort | tr '\n' ' ')"
import_re='^[[:space:]]*import (AppKit|Cocoa|SwiftUI)'

# shellcheck disable=SC2086 # the folders are deliberately word-split
offenders="$(grep -rlE "$import_re" --include='*.swift' $engine_dirs | sort || true)"

if [ -n "$offenders" ]; then
  {
    printf '[FAIL] app-only sources compiled into OpenSkyCLI:\n'
    printf '%s\n' "$offenders" | sed 's/^/  /'
    printf 'These import AppKit/Cocoa/SwiftUI but live under %s, which\n' "$engine_dirs"
    printf 'the OpenSkyCLI target builds or links.\n'
    printf 'Fix: move the file to Sources/OpenSky/ with git mv, or drop the import.\n'
  } >&2
  exit 1
fi

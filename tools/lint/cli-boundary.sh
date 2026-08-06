#!/bin/sh
# CLI target-boundary lint (issues #109, #336). Target membership follows the
# folder split under opensky/: App/ builds only into the app, Engine/ and
# SharedHeaders/ build into both the app and openskycli. So an AppKit, Cocoa, or
# SwiftUI import anywhere under Engine/ enters the CLI build and breaks it. This
# asserts there are none — catches the break at commit time, no CLI build.
set -eu

cd "$(git rev-parse --show-toplevel)"

engine_dir="opensky/Engine"
import_re='^[[:space:]]*import (AppKit|Cocoa|SwiftUI)'

offenders="$(grep -rlE "$import_re" --include='*.swift' "$engine_dir" | sort || true)"

if [ -n "$offenders" ]; then
  {
    printf '[FAIL] app-only sources compiled into openskycli:\n'
    printf '%s\n' "$offenders" | sed 's/^/  /'
    printf 'These import AppKit/Cocoa/SwiftUI but live under %s/, which the\n' "$engine_dir"
    printf 'openskycli target synchronizes.\n'
    printf 'Fix: move the file to opensky/App/ with git mv, or drop the import.\n'
  } >&2
  exit 1
fi

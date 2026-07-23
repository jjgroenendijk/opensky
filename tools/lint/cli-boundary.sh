#!/bin/sh
# CLI target-boundary lint (issue #109). Filesystem-synced groups make every
# new file under opensky/ join ALL targets syncing that folder, so app-only
# (AppKit/Cocoa/SwiftUI) sources silently enter the openskycli build unless
# listed in the target's membershipExceptions. This asserts the exception list
# covers every such file — catches the break at commit time, no CLI build.
set -eu

cd "$(git rev-parse --show-toplevel)"

pbxproj="opensky.xcodeproj/project.pbxproj"
src_dir="opensky"
import_re='^[[:space:]]*import (AppKit|Cocoa|SwiftUI)'

# Entries of the "opensky" folder exception set for the openskycli target.
# Anchor on Xcode's own section comment; strip indentation, quotes, commas.
exceptions="$(awk '
  /Exceptions for "opensky" folder in "openskycli" target/ { in_set = 1 }
  in_set && /membershipExceptions = \(/ { in_list = 1; next }
  in_list && /\);/ { exit }
  in_list {
    gsub(/^[[:space:]]+/, ""); gsub(/,[[:space:]]*$/, ""); gsub(/"/, "")
    print
  }
' "$pbxproj")"

importers="$(grep -rlE "$import_re" --include='*.swift' "$src_dir" \
  | sed "s|^$src_dir/||" | sort || true)"

missing=""
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  printf '%s\n' "$exceptions" | grep -qxF "$rel" || missing="$missing  $src_dir/$rel
"
done <<EOF
$importers
EOF

if [ -n "$missing" ]; then
  {
    printf '[FAIL] app-only sources compiled into openskycli:\n%s' "$missing"
    printf 'These import AppKit/Cocoa/SwiftUI but lack a membershipException, so\n'
    printf 'the filesystem-synced group pulls them into the CLI target.\n'
    printf 'Fix: Xcode File Inspector -> uncheck openskycli target membership,\n'
    printf 'or add the path to membershipExceptions of the set\n'
    printf '"Exceptions for \\"opensky\\" folder in \\"openskycli\\" target"\n'
    printf 'in %s.\n' "$pbxproj"
  } >&2
  exit 1
fi

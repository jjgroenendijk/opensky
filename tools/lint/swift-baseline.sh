#!/bin/sh
# Swift toolchain + language-mode baseline (issue #314).
#
# Two things regress silently and are cheap to assert:
#
#   1. The compiler. OpenSky is written against Apple Swift 6.3.3 (Xcode 26.6).
#      An older toolchain rejects code this repository already contains, and
#      the resulting diagnostics point at the source rather than at the
#      toolchain, so the check names the version it found.
#   2. The language mode. Every Xcode build configuration must stay on Swift 6.
#      A single configuration slipping back to 5.0 disables strict concurrency
#      checking for a whole target without failing any other gate.
#
# Build settings now live in Config/*.xcconfig (issue #343) with only structural
# entries left in the pbxproj, so the language-mode scan reads both: the xcconfig
# layer is where SWIFT_VERSION is set today, and a setting reintroduced in the
# project file would silently override it.
set -eu

cd "$(git rev-parse --show-toplevel)"

# Minimum supported Apple Swift release, as three integers.
required_major=6
required_minor=3
required_patch=3
required="$required_major.$required_minor.$required_patch"

# Language mode every SWIFT_VERSION build setting must carry.
required_language_mode="6.0"

pbxproj="opensky.xcodeproj/project.pbxproj"

if ! command -v swiftc >/dev/null 2>&1; then
  printf '[FAIL] swiftc not found. Install Xcode 26 and run: make bootstrap\n' >&2
  exit 1
fi

# "swift-driver version: ... Apple Swift version 6.3.3 (swiftlang-6.3.3.1.3 ...)"
version_line="$(swiftc --version 2>&1 | grep -m1 'Apple Swift version' || true)"
if [ -z "$version_line" ]; then
  {
    printf '[FAIL] could not read an Apple Swift version from swiftc --version:\n'
    swiftc --version 2>&1 | sed 's/^/       /'
    printf '       OpenSky requires the Apple toolchain shipped with Xcode 26.\n'
  } >&2
  exit 1
fi

found="$(printf '%s\n' "$version_line" \
  | sed -n 's/.*Apple Swift version \([0-9][0-9.]*\).*/\1/p')"
found_major="$(printf '%s\n' "$found" | cut -d. -f1)"
found_minor="$(printf '%s\n' "$found" | cut -d. -f2)"
found_patch="$(printf '%s\n' "$found" | cut -d. -f3)"
# A two-component release such as "6.3" reports patch 0.
[ -n "$found_minor" ] || found_minor=0
[ -n "$found_patch" ] || found_patch=0

too_old=0
if [ "$found_major" -lt "$required_major" ]; then
  too_old=1
elif [ "$found_major" -eq "$required_major" ]; then
  if [ "$found_minor" -lt "$required_minor" ]; then
    too_old=1
  elif [ "$found_minor" -eq "$required_minor" ] && [ "$found_patch" -lt "$required_patch" ]; then
    too_old=1
  fi
fi

if [ "$too_old" -eq 1 ]; then
  {
    printf '[FAIL] Apple Swift %s is older than the supported baseline %s.\n' \
      "$found" "$required"
    printf '       swiftc: %s\n' "$(command -v swiftc)"
    printf '       Select the Xcode 26 toolchain, e.g.\n'
    printf '       sudo xcode-select -s /Applications/Xcode.app\n'
  } >&2
  exit 1
fi

if [ ! -f "$pbxproj" ]; then
  printf '[FAIL] %s not found\n' "$pbxproj" >&2
  exit 1
fi

# Every place a build setting can be declared. Config/Local.xcconfig is gitignored
# and only carries signing, so the glob covering it costs nothing.
sources="$(ls Config/*.xcconfig 2>/dev/null || true)"
# shellcheck disable=SC2086 # sources is a newline-separated file list, not one path.
modes="$(awk '/SWIFT_VERSION = /{ n++ } END { print n + 0 }' "$pbxproj" $sources)"
if [ "$modes" -eq 0 ]; then
  printf '[FAIL] no SWIFT_VERSION build setting in %s or Config/*.xcconfig\n' \
    "$pbxproj" >&2
  exit 1
fi

# The pbxproj spells settings with a trailing semicolon, xcconfig files without one.
# shellcheck disable=SC2086 # sources is a newline-separated file list, not one path.
stale="$(grep -n 'SWIFT_VERSION = ' "$pbxproj" $sources \
  | grep -v "SWIFT_VERSION = $required_language_mode;" \
  | grep -v "SWIFT_VERSION = $required_language_mode\$" || true)"
if [ -n "$stale" ]; then
  {
    printf '[FAIL] build configurations not in Swift %s language mode:\n' \
      "$required_language_mode"
    printf '%s\n' "$stale" | sed 's/^/       /'
    printf '       Every SWIFT_VERSION in %s and Config/*.xcconfig must read %s.\n' \
      "$pbxproj" "$required_language_mode"
  } >&2
  exit 1
fi

printf '[ OK ] Apple Swift %s (baseline %s), %s declaration(s) in Swift %s mode\n' \
  "$found" "$required" "$modes" "$required_language_mode"

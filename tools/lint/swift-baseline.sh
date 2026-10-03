#!/bin/sh
# Swift toolchain + language-mode baseline (issue #314).
#
# Two things drift silently and are cheap to assert:
#
#   1. The compiler. Local builds and CI must use the same Apple Swift. Each
#      release accepts code the other rejects, so a mismatch passes here and
#      fails in CI, or the reverse. CI names its Xcode in DEVELOPER_DIR
#      (.github/workflows/ci.yml); change it together with required below.
#   2. The language mode. Every Xcode build configuration must stay on Swift 6.
#      A single configuration slipping back to 5.0 disables strict concurrency
#      checking for a whole target without failing any other gate.
#
# Build settings live in Config/Build/*.xcconfig with only structural entries left
# in the pbxproj, so the language-mode scan reads both: a setting reintroduced in
# the project file would silently override the xcconfig layer.
set -eu

cd "$(git rev-parse --show-toplevel)"

# The Apple Swift release of the Xcode that CI selects. A release without a
# patch number, such as "6.4", also matches "6.4.0".
required="6.4"

# Language mode every SWIFT_VERSION build setting must carry.
required_language_mode="6.0"

pbxproj="OpenSky.xcodeproj/project.pbxproj"

if ! command -v swiftc >/dev/null 2>&1; then
  printf '[FAIL] swiftc not found. Install Xcode and run: make bootstrap\n' >&2
  exit 1
fi

# "swift-driver version: ... Apple Swift version 6.4 (swiftlang-6.4.0.34.1 ...)"
version_line="$(swiftc --version 2>&1 | grep -m1 'Apple Swift version' || true)"
if [ -z "$version_line" ]; then
  {
    printf '[FAIL] could not read an Apple Swift version from swiftc --version:\n'
    swiftc --version 2>&1 | sed 's/^/       /'
    printf '       OpenSky requires the Apple toolchain shipped with Xcode.\n'
  } >&2
  exit 1
fi

found="$(printf '%s\n' "$version_line" \
  | sed -n 's/.*Apple Swift version \([0-9][0-9.]*\).*/\1/p')"

if [ "${found%.0}" != "${required%.0}" ]; then
  {
    printf '[FAIL] Apple Swift %s, but CI builds with Apple Swift %s.\n' "$found" "$required"
    printf '       swiftc: %s\n' "$(command -v swiftc)"
    printf '       Select the matching Xcode (sudo xcode-select -s <Xcode.app>), or move\n'
    printf '       DEVELOPER_DIR in .github/workflows/ci.yml and required here together.\n'
  } >&2
  exit 1
fi

if [ ! -f "$pbxproj" ]; then
  printf '[FAIL] %s not found\n' "$pbxproj" >&2
  exit 1
fi

# Every place a build setting can be declared. An optional gitignored
# Config/Build/Local.xcconfig only carries signing, so the glob covering it costs nothing.
sources="$(ls Config/Build/*.xcconfig 2>/dev/null || true)"
# shellcheck disable=SC2086 # sources is a newline-separated file list, not one path.
modes="$(awk '/SWIFT_VERSION = /{ n++ } END { print n + 0 }' "$pbxproj" $sources)"
if [ "$modes" -eq 0 ]; then
  printf '[FAIL] no SWIFT_VERSION build setting in %s or Config/Build/*.xcconfig\n' \
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
    printf '       Every SWIFT_VERSION in %s and Config/Build/*.xcconfig must read %s.\n' \
      "$pbxproj" "$required_language_mode"
  } >&2
  exit 1
fi

printf '[ OK ] Apple Swift %s (same as CI), %s declaration(s) in Swift %s mode\n' \
  "$found" "$modes" "$required_language_mode"

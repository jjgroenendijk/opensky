#!/bin/sh
# Load order check. Engine code and tools read records through the whole load
# order (`ActiveLoadOrder`), never one plugin alone, so a DLC or mod record is
# never missed. Only the opener itself and the format parsers may open a plugin.
set -eu
# shellcheck source=tools/checks-lib.sh
. "$(dirname "$0")/../checks-lib.sh"
if [ "${1:-}" = --self-check ]; then
    tree="$(self_check_tree)"
    mkdir -p "$tree/src/Sources/OpenSkyX"
    echo 'let file = try ESMFile(url: url)' >"$tree/src/Sources/OpenSkyX/A.swift"
    expect_failure "$0" "$tree" "a plugin is opened alone"
fi

cd "$(git rev-parse --show-toplevel)"

report="$(
  git ls-files -z -- 'src/Sources/*.swift' |
    xargs -0 grep -n 'ESMFile(url:' |
    grep -v -e '^src/Sources/OpenSkyFormats' -e '^src/Sources/OpenSkyGameData/ActivePluginFiles.swift:' ||
    true
)"

if [ -z "$report" ]; then
  printf '[ OK ] plugins open only through the load order\n'
  exit 0
fi
printf '%s\n' "$report"
printf '[FAIL] a plugin is opened alone. Use ActiveLoadOrder.open(root:) instead.\n' >&2
exit 1

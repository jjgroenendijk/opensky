#!/bin/sh
# Load order check. Engine code and tools read records through the whole load
# order (`ActiveLoadOrder`), never one plugin alone, so a DLC or mod record is
# never missed. Only the opener itself and the format parsers may open a plugin.
set -eu

cd "$(git rev-parse --show-toplevel)"

report="$(
  git ls-files -z -- 'Sources/*.swift' |
    xargs -0 grep -n 'ESMFile(url:' |
    grep -v -e '^Sources/OpenSkyFormats' -e '^Sources/OpenSkyGameData/ActivePluginFiles.swift:' ||
    true
)"

if [ -z "$report" ]; then
  printf '[ OK ] plugins open only through the load order\n'
  exit 0
fi
printf '%s\n' "$report"
printf '[FAIL] a plugin is opened alone. Use ActiveLoadOrder.open(root:) instead.\n' >&2
exit 1

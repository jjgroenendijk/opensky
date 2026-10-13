#!/bin/sh
# Gap registry check. `openskycli gaps` counts a NIF block type as handled when
# NIFBlockTypes.handled lists it, so that list must hold exactly the type names
# engine code names. It fails on a type name the code uses that the list lacks, and
# on a listed name no code uses. Behaviour class names live in the animation
# modules, so those are not scanned (docs/tools/gaps.md).
set -eu

cd "$(git rev-parse --show-toplevel)"
registry=Sources/OpenSkyFormatsMesh/NIF/NIFBlockTypes.swift
pattern='"(Ni|BS|bhk|hk)[A-Z][A-Za-z0-9]*"'

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
git ls-files -- 'Sources/*.swift' |
  grep -vE '^Sources/(OpenSkyFormatsAnimation|OpenSkyBehavior|OpenSkyCLI)/' |
  grep -vxF "$registry" |
  xargs grep -ohE "$pattern" | tr -d '"' | LC_ALL=C sort -u >"$work/used"
grep -ohE "$pattern" "$registry" | tr -d '"' | LC_ALL=C sort -u >"$work/listed"
missing="$(LC_ALL=C comm -23 "$work/used" "$work/listed")"
stale="$(LC_ALL=C comm -13 "$work/used" "$work/listed")"

status=0
for name in $missing; do
  printf '%s: code names %s; add it to NIFBlockTypes.handled\n' "$registry" "$name"
  status=1
done
for name in $stale; do
  printf '%s: lists %s, which no code names; remove it\n' "$registry" "$name"
  status=1
done
if [ "$status" -eq 0 ]; then
  printf '[ OK ] gap registries match the code\n'
else
  printf '[FAIL] gap registries differ from the code\n' >&2
fi
exit "$status"

#!/bin/sh
# File-length check. A long file mixes several jobs and is slow to review, so a
# text file over 600 lines gets a warning and one over 800 lines fails.
# Default: the files the branch changed. --staged: the staged content, for the
# pre-commit hook. --all: every tracked file.
set -eu

warn=600
limit=800
cd "$(git rev-parse --show-toplevel)"

mode="${1:-}"
case "$mode" in
--staged) files="$(git diff --cached --name-only --diff-filter=AMR)" ;;
--all) files="$(git ls-files)" ;;
"")
  base="$(git merge-base HEAD origin/main 2>/dev/null || echo HEAD)"
  files="$({
    git diff --name-only --diff-filter=AMR "$base"
    git ls-files --others --exclude-standard
  } | sort -u)"
  ;;
*)
  echo "usage: $0 [--staged | --all]" >&2
  exit 2
  ;;
esac

content() {
  if [ "$mode" = --staged ]; then git show ":$1"; else cat "$1"; fi
}

failed=0
warned=0
for file in $files; do
  case "$file" in
  *.pbxproj | *Package.resolved) continue ;; # written by tools, not people
  Package.swift) continue ;;                  # SwiftPM reads one manifest file only
  esac
  [ "$mode" = --staged ] || [ -f "$file" ] || continue
  content "$file" | grep -Iq . || continue # binary or empty
  lines="$(content "$file" | wc -l | tr -d ' ')"
  if [ "$lines" -gt "$limit" ]; then
    printf '[ERROR] %s has %s lines; the limit is %s. Split it below %s.\n' \
      "$file" "$lines" "$limit" "$warn" >&2
    failed=$((failed + 1))
  elif [ "$lines" -gt "$warn" ]; then
    printf '[WARNING] %s has %s lines, over %s. Split it before it passes %s.\n' \
      "$file" "$lines" "$warn" "$limit"
    warned=$((warned + 1))
  fi
done

if [ "$failed" -gt 0 ]; then
  printf '[FAIL] %s files over %s lines\n' "$failed" "$limit" >&2
  exit 1
fi
printf '[ OK ] no file over %s lines (%s over %s)\n' "$limit" "$warned" "$warn"

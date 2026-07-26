#!/bin/sh
# Game-content lint (AGENTS.md "Legal & IP boundary"). Two rules, one source of
# truth so the pre-commit hook and `make lint` cannot drift apart:
#
#   1. Extracted Bethesda assets must never be committed, in any form.
#   2. A frame OpenSky renders embeds the user's own game textures and meshes,
#      so a rendered capture is game content too. Only the app icon set is a
#      legitimately tracked image; verification captures go to gitignored logs/.
#
# Default: every tracked file. `--staged`: only files staged for the next
# commit (what the pre-commit hook checks). The tracked-tree mode also catches
# a blob that arrived by merge or rebase rather than by `git add`.
set -eu

cd "$(git rev-parse --show-toplevel)"

FORBIDDEN_EXT_RE='\.(bsa|ba2|esm|esp|esl|nif|dds|hkx|hkc|pex|psc|bik|fuz|xwm|lip|tri|btr|bto|btt)$'
RENDERED_IMAGE_RE='\.(png|jpg|jpeg|gif|webp|tga|bmp|tif|tiff)$'
ALLOWED_IMAGE_PATH_RE='^opensky/Assets\.xcassets/'

indent() { while IFS= read -r line; do printf '  %s\n' "$line"; done; }

case "${1:-}" in
  --staged) files="$(git diff --cached --name-only --diff-filter=ACM)" ;;
  '') files="$(git ls-files)" ;;
  *)
    printf '[FAIL] usage: %s [--staged]\n' "$0" >&2
    exit 2
    ;;
esac

assets="$(printf '%s\n' "$files" | grep -Ei "$FORBIDDEN_EXT_RE" || true)"
if [ -n "$assets" ]; then
  {
    printf '[FAIL] These look like extracted game assets:\n'
    printf '%s\n' "$assets" | indent
    printf 'Game content must never be committed, not even as a test fixture.\n'
    printf 'Fix: git rm --cached <file>, and use a synthetic in-code fixture.\n'
  } >&2
  exit 1
fi

images="$(printf '%s\n' "$files" | grep -Ei "$RENDERED_IMAGE_RE" \
  | grep -Ev "$ALLOWED_IMAGE_PATH_RE" || true)"
if [ -n "$images" ]; then
  {
    printf '[FAIL] Tracked image outside the app asset catalog:\n'
    printf '%s\n' "$images" | indent
    printf 'A frame OpenSky renders embeds Bethesda assets, so captures are\n'
    printf 'game content even as milestone evidence.\n'
    printf 'Fix: write it to logs/ (gitignored) and link the local path in the\n'
    printf 'PR body instead of committing it.\n'
  } >&2
  exit 1
fi

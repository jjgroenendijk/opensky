#!/bin/sh
# Agent instruction files. Claude Code loads a nested CLAUDE.md, not a nested
# AGENTS.md, so every tracked AGENTS.md needs a CLAUDE.md symlink beside it or
# it never loads. Each skill keeps the limits of the Agent Skills format: a
# `name` equal to its folder, a description of at most 1024 characters, a body
# of at most 500 lines, and an evals.json with at least three scenarios.
set -eu

cd "$(git rev-parse --show-toplevel)"

status=0
fail() {
  printf '[FAIL] %s\n' "$1" >&2
  status=1
}

for agents in $(git ls-files -- 'AGENTS.md' '*/AGENTS.md'); do
  dir="$(dirname "$agents")"
  link="$dir/CLAUDE.md"
  if [ ! -L "$link" ] || [ "$(readlink "$link")" != "AGENTS.md" ]; then
    fail "$link must be a symlink to AGENTS.md: ln -s AGENTS.md $link"
  fi
done

for skill_dir in .AGENTS/skills/*/; do
  skill="$(basename "$skill_dir")"
  file="${skill_dir}SKILL.md"
  if [ ! -f "$file" ]; then
    fail "$skill_dir has no SKILL.md"
    continue
  fi

  name="$(sed -n 's/^name: *//p' "$file" | head -n 1)"
  [ "$name" = "$skill" ] || fail "$file: name '$name' must equal the folder name '$skill'"

  # The description may wrap onto indented continuation lines.
  description="$(awk '
    /^description:/ { sub(/^description: */, ""); text = $0; open = 1; next }
    open && /^  / { sub(/^ +/, ""); text = text " " $0; next }
    open { exit }
    END { print text }
  ' "$file")"
  length="$(printf '%s' "$description" | wc -c | tr -d ' ')"
  [ "$length" -gt 0 ] || fail "$file has no description"
  [ "$length" -le 1024 ] || fail "$file: description has $length characters; the limit is 1024"

  lines="$(wc -l <"$file" | tr -d ' ')"
  [ "$lines" -le 500 ] || fail "$file has $lines lines; the limit is 500. Move detail to a reference file"

  evals="${skill_dir}evals.json"
  if [ ! -f "$evals" ]; then
    fail "$skill_dir has no evals.json"
    continue
  fi
  if ! python3 - "$evals" "$skill" <<'PY'
import json
import sys

path, skill = sys.argv[1], sys.argv[2]
try:
    with open(path, encoding="utf-8") as handle:
        scenarios = json.load(handle)
except (OSError, ValueError) as error:
    sys.exit(f"[FAIL] {path}: {error}")
if not isinstance(scenarios, list) or len(scenarios) < 3:
    sys.exit(f"[FAIL] {path}: needs a list of at least three scenarios")
for index, scenario in enumerate(scenarios):
    # An empty "skills" list is a scenario where the skill must not load.
    missing = [key for key in ("skills", "query", "expected_behavior") if key not in scenario]
    missing += [key for key in ("query", "expected_behavior") if key in scenario and not scenario[key]]
    if missing:
        sys.exit(f"[FAIL] {path}: scenario {index} has no {', '.join(missing)}")
if not any(skill in scenario["skills"] for scenario in scenarios):
    sys.exit(f"[FAIL] {path}: no scenario expects the skill '{skill}'")
PY
  then
    status=1
  fi
done

[ "$status" -eq 0 ] && printf '[ OK ] agent files and skills line up\n'
exit "$status"

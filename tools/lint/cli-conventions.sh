#!/bin/sh
# openskycli conventions that need the source, not the parsed command tree. Every leaf
# command has a runner, a row in docs/tools/cli.md, and a run in a probe script (or a
# reason in cli-probe-exceptions.txt), and a number option is not declared as a String.
# The tree-level rules are CLIConventionTests in OpenSkyCLIArgumentsTests.
set -eu

cd "$(git rev-parse --show-toplevel)"

arguments_dir=Sources/OpenSkyCLIArguments
exceptions=tools/lint/cli-probe-exceptions.txt
failed=0

# One "<type path><TAB><command path>" line per leaf command, from the declarations.
leaves="$(
  awk '
    function path_of(type,    parts, n, i, p) {
      n = split(type, parts, ".")
      p = ""
      for (i = 1; i <= n; i++) {
        key = parts[1]
        for (j = 2; j <= i; j++) key = key "." parts[j]
        if (!(key in name)) return ""
        p = (p == "" ? name[key] : p " " name[key])
      }
      return p
    }
    function current(    i, t) {
      t = ""
      for (i = 1; i <= depth; i++) t = (t == "" ? stack[i] : t "." stack[i])
      return t
    }
    /^ *(public )?(struct|extension) [A-Za-z]+/ {
      match($0, /^ */); indent = RLENGTH
      line = $0
      sub(/^ *(public )?(struct|extension) /, "", line)
      match(line, /^[A-Za-z]+/)
      type = substr(line, 1, RLENGTH)
      depth++; stack[depth] = type; indents[depth] = indent
      if ($0 ~ /: (CLICommandArguments|AssetCacheActionArguments)/) leaf[current()] = 1
      next
    }
    /^ *public enum [A-Za-z]+: GMSTSubjectKind/ { subject = 1; next }
    subject && /static let name = "/ {
      match($0, /"[^"]+"/); subjects[++nsubjects] = substr($0, RSTART + 1, RLENGTH - 2)
      subject = 0; next
    }
    /commandName: "/ {
      match($0, /"[^"]+"/); name[current()] = substr($0, RSTART + 1, RLENGTH - 2)
    }
    /shouldDisplay: false/ { hidden[current()] = 1 }
    /^ *}$/ {
      match($0, /^ */)
      if (depth > 0 && RLENGTH == indents[depth]) depth--
    }
    END {
      for (type in leaf) {
        if (type in hidden) continue
        if (type == "GMSTArguments.Subject") {
          for (i = 1; i <= nsubjects; i++) print type "\t" name["GMSTArguments"] " " subjects[i]
          continue
        }
        p = path_of(type)
        if (p != "") print type "\t" p
      }
    }
  ' "$arguments_dir"/*.swift | sort
)"

if [ "$(printf '%s\n' "$leaves" | grep -c .)" -lt 40 ]; then
  printf "[FAIL] found only a few leaf commands; the declaration scan is broken\n" >&2
  exit 1
fi

tab="$(printf '\t')"
while IFS="$tab" read -r type path; do
  if ! grep -rqF "extension $type: CLIRunnable" Sources/OpenSkyCLI; then
    printf "[FAIL] %s (%s) has no CLIRunnable runner in Sources/OpenSkyCLI\n" "$path" "$type" >&2
    failed=1
  fi
  if ! grep -qF "\`$path" docs/tools/cli.md; then
    printf "[FAIL] \`%s\` has no row in docs/tools/cli.md\n" "$path" >&2
    failed=1
  fi
  if ! cat tools/probe.sh tools/probe-swf.sh | grep -qE "(^|[ \"])$path([ \"]|\$)" &&
    ! grep -qE "^$path:" "$exceptions"; then
    printf "[FAIL] \`%s\` is not run by tools/probe.sh or tools/probe-swf.sh; add a run or a reason to %s\n" \
      "$path" "$exceptions" >&2
    failed=1
  fi
done <<EOF
$leaves
EOF

# Every exception names a real command, so the list cannot go stale.
while IFS=: read -r path _; do
  case "$path" in '' | '#'*) continue ;; esac
  if ! printf '%s\n' "$leaves" | cut -f2 | grep -qxF "$path"; then
    printf "[FAIL] %s lists \`%s\`, which is no command\n" "$exceptions" "$path" >&2
    failed=1
  fi
done <"$exceptions"

# A number option declared as a String skips the parser's check.
strings="$(
  awk '
    /@Option\(/ { collecting = 1; text = "" }
    collecting { text = text $0 }
    collecting && /public var / {
      if (text ~ /valueName: "(n|s|seconds|deg|units|hour|factor|pixels)"/ &&
          ($0 ~ /: String/ || $0 ~ /= "/)) print FILENAME ":" FNR ": " $0
      collecting = 0
    }
  ' "$arguments_dir"/*.swift
)"
if [ -n "$strings" ]; then
  printf '%s\n' "$strings"
  printf "[FAIL] a number option is a String; declare it Int, Int32, Float, or Double\n" >&2
  failed=1
fi

# tools/new-cli-command.sh writes TODO stubs; none may land.
todos="$(
  grep -nF 'TODO' "$arguments_dir"/*.swift tools/probe.sh
  grep -nE '^\|.*TODO' docs/tools/cli.md
)" || true
if [ -n "$todos" ]; then
  printf '%s\n' "$todos"
  printf "[FAIL] a new command still has TODO stubs from make new-cli-command\n" >&2
  failed=1
fi

[ "$failed" -eq 0 ] || exit 1
printf '[ OK ] %s openskycli commands have a runner, a docs row, and a probe run\n' \
  "$(printf '%s\n' "$leaves" | grep -c .)"

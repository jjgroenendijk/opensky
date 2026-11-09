#!/bin/sh
# Design rule 1, as a report: every Swift file under src/ against the tighter size limits in
# tools/design/size.swiftlint.yml. Prints each finding, then the count per rule and module.
# Fails nothing; the limits move into the lint config when the count is zero.
set -eu
cd "$(git rev-parse --show-toplevel)"
findings="$(git ls-files 'src/*.swift' \
    | xargs swiftlint lint --quiet --config tools/design/size.swiftlint.yml 2>/dev/null || true)"
printf '%s\n' "$findings" | sed "s|^$(pwd)/||" | grep . || true
printf '%s\n' "$findings" | python3 -c '
import collections, re, sys
counts = collections.Counter()
for line in sys.stdin:
    rule = re.search(r"\((\w+)\)$", line.strip())
    module = re.search(r"/src/(?:Sources|Tests)/([^/]+)/", line)
    if rule:
        counts[(rule.group(1), module.group(1) if module else "other")] += 1
print("[INFO] design rule 1, size limits:")
for rule in sorted({rule for rule, _ in counts}):
    total = sum(n for (r, _), n in counts.items() if r == rule)
    print(f"  {rule}: {total}")
    for (r, module), n in sorted(counts.items(), key=lambda item: -item[1]):
        if r == rule:
            print(f"    {module}: {n}")
print(f"[INFO] {sum(counts.values())} findings in all")
'

#!/bin/sh
# actionlint over the GitHub Actions workflows.
set -eu
# shellcheck source=tools/checks-lib.sh
. "$(dirname "$0")/../checks-lib.sh"
if [ "${1:-}" = --self-check ]; then
    tree="$(self_check_tree)"
    mkdir -p "$tree/.github/workflows"
    cat >"$tree/.github/workflows/a.yml" <<'YAML'
on: push
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - run: echo ${{ github.nope }}
YAML
    expect_failure "$0" "$tree" "github.nope"
fi
config="$OPENSKY_TOOLS/lint/actionlint.yaml"
cd "$(git rev-parse --show-toplevel)"
actionlint -config-file "$config"
echo "[ OK ] workflows clean"

#!/bin/sh
# Refuse to commit extracted game content or rendered captures.
# Shares its rules with `make no-game-content` so the hook and CI agree.
set -eu

exec "$(git rev-parse --show-toplevel)/tools/lint/no-game-content.sh" --staged

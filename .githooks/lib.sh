# POSIX sh helpers for OpenSky hook scripts.
# Source: . "$(git rev-parse --show-toplevel)/.githooks/lib.sh"
# shellcheck shell=sh

ROOT="$(git rev-parse --show-toplevel)"
export ROOT

hook_info() { printf '[INFO] %s\n' "$*"; }
hook_ok()   { printf '[ OK ] %s\n' "$*"; }
hook_warn() { printf '[WARN] %s\n' "$*" >&2; }
hook_fail() { printf '[FAIL] %s\n' "$*" >&2; }

# Abort with a pointer to bootstrap when a required tool is missing.
require_tool() {
  command -v "$1" >/dev/null 2>&1 && return 0
  hook_fail "'$1' not found. Run: make bootstrap"
  exit 1
}

# Staged files (Added/Copied/Modified) matching an extended-regex, newline-separated.
staged_matching() {
  git diff --cached --name-only --diff-filter=ACM | grep -E "$1" || true
}

# Extensions that indicate extracted Bethesda/game content (AGENTS.md "Legal & IP").
# shellcheck disable=SC2034  # sourced + used by pre-commit/20-no-game-content.sh
FORBIDDEN_EXT_RE='\.(bsa|ba2|esm|esp|esl|nif|dds|hkx|hkc|pex|psc|bik|fuz|xwm|lip|tri|btr|bto|btt)$'

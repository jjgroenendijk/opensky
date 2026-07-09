#!/bin/sh
# OpenSky one-shot dev bootstrap: install tools + wire git hooks. Idempotent.
# Invoked by `make bootstrap`.
set -eu

cd "$(git rev-parse --show-toplevel)"

echo "[INFO] Checking toolchain..."
if ! command -v brew >/dev/null 2>&1; then
  echo "[FAIL] Homebrew required: https://brew.sh" >&2
  exit 1
fi

# Formatters + linters are mandatory (AGENTS.md "Code quality").
for tool in swiftformat swiftlint markdownlint-cli2 shellcheck; do
  if command -v "$tool" >/dev/null 2>&1; then
    echo "  [ OK ] $tool"
  else
    echo "  [INFO] installing $tool"
    brew install "$tool"
  fi
done

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "  [WARN] xcodebuild not found — install Xcode from the App Store." >&2
fi

echo "[INFO] Wiring git hooks (.githooks/hooks)..."
git config core.hooksPath .githooks/hooks
find .githooks -type f \( -name '*.sh' -o -path '*/hooks/*' \) -exec chmod +x {} +
echo "  [ OK ] core.hooksPath = $(git config --get core.hooksPath)"

echo "[ OK ] Bootstrap complete. Try: make check"

#!/bin/sh
# Make sure Config/Local.xcconfig exists before any xcodebuild call.
#
# Config/Base.xcconfig ends its signing block with `#include? "Local.xcconfig"`, so the
# file is optional as far as Xcode is concerned; the defaults in Base are ad-hoc signing
# and every target builds without it. It still gets created eagerly, because the file is
# where a developer sets their signing identity and a file that does not exist is a file
# nobody edits. A missing template, on the other hand, means the checkout is broken, so
# that fails loudly with what to do about it.
#
# A linked worktree copies the main checkout's Local.xcconfig rather than the template:
# every worktree of this repository signs with the same identity, and re-deriving it per
# worktree would silently downgrade a dev-signed build to ad-hoc.
#
# Invoked by `make bootstrap` and by every xcodebuild-driving make target. Idempotent,
# and silent when there is nothing to do.
set -eu

root=$(git rev-parse --show-toplevel)
cd "$root"

local_config="$root/Config/Local.xcconfig"
template="$root/Config/Local.example.xcconfig"

[ ! -f "$local_config" ] || exit 0

if [ ! -f "$template" ]; then
  {
    echo "[FAIL] $template is missing, so Config/Local.xcconfig cannot be created."
    echo "       It is checked in; restore it with: git checkout -- Config/Local.example.xcconfig"
  } >&2
  exit 1
fi

# In the main checkout --git-common-dir is the checkout's own .git, so `shared` resolves
# back to `root` and the branch below is simply skipped.
common=$(git rev-parse --git-common-dir)
shared=$(cd "$(dirname "$common")" && pwd)

if [ "$root" != "$shared" ] && [ -f "$shared/Config/Local.xcconfig" ]; then
  cp "$shared/Config/Local.xcconfig" "$local_config"
  echo "  [ OK ] copied Config/Local.xcconfig from $shared"
  exit 0
fi

cp "$template" "$local_config"
echo "  [INFO] created Config/Local.xcconfig from Config/Local.example.xcconfig."
echo "         It signs ad-hoc. Set OPENSKY_CODE_SIGN_IDENTITY and"
echo "         OPENSKY_DEVELOPMENT_TEAM there to sign with your Apple Development"
echo "         identity instead; the file is gitignored."

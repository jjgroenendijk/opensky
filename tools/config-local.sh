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
# When there is nothing to copy, the file is generated around whatever Apple Development
# identity the login keychain holds, and only falls back to the ad-hoc template when there
# is none. Ad-hoc signing produces a different code signature on every build, so macOS
# sees each build as a new application and re-asks for Automation and for access to the
# volume the game install sits on. That turns `make test-ui` and every real-data test into
# a sequence of permission dialogs, which is not something a developer should have to
# discover by being interrupted.
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

# The common name of the first Apple Development identity in the keychain, empty when
# there is none. `security find-identity -v -p codesigning` prints one indented line per
# identity, `  1) <sha1> "<common name>"`.
identity_name=$(
  security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/^ *[0-9]*) [0-9A-F]* "\(Apple Development: [^"]*\)"$/\1/p' \
    | head -1
)

# The Team ID is the OU of that certificate. Reading it beats asking a developer to copy
# it out of the developer portal, and it is the value Xcode itself matches against.
team=""
if [ -n "$identity_name" ]; then
  team=$(
    security find-certificate -c "$identity_name" -p 2>/dev/null \
      | openssl x509 -noout -subject 2>/dev/null \
      | tr ',/' '\n' \
      | sed -n 's/^ *OU=\([A-Z0-9]\{10\}\)$/\1/p' \
      | head -1
  )
fi

# Both halves or neither: CODE_SIGN_STYLE is Automatic, and a real identity without a team
# fails to resolve a provisioning profile instead of quietly signing ad-hoc.
if [ -z "$identity_name" ] || [ -z "$team" ]; then
  cp "$template" "$local_config"
  echo "  [INFO] created Config/Local.xcconfig from Config/Local.example.xcconfig."
  echo "         No Apple Development identity was found in the keychain, so it signs"
  echo "         ad-hoc and macOS re-asks for permissions on every build. Set"
  echo "         OPENSKY_CODE_SIGN_IDENTITY and OPENSKY_DEVELOPMENT_TEAM there once you"
  echo "         have an identity; the file is gitignored."
  exit 0
fi

cat >"$local_config" <<CONFIG
// Per-developer signing, gitignored, written by tools/config-local.sh from the Apple
// Development identity in this machine's keychain. Edit it freely; it is never
// regenerated once it exists.
//
// Signing with a real identity keeps this machine's TCC grants (Automation, Files and
// Folders, access to the volume the game install sits on) across builds. Ad-hoc signing
// gives the binary a new signature every build, so macOS treats each build as a new
// application and asks again.
//
// Set OPENSKY_CODE_SIGN_IDENTITY to - and clear OPENSKY_DEVELOPMENT_TEAM to sign ad-hoc,
// which is what CI does.

OPENSKY_CODE_SIGN_IDENTITY = Apple Development
OPENSKY_DEVELOPMENT_TEAM = $team
CONFIG

echo "  [ OK ] created Config/Local.xcconfig signing with \"$identity_name\" (team $team)."

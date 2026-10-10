#!/bin/sh
# Check, and guide, the one-time macOS TCC grants that test runs depend on.
#
# Why this is a helper and not a fully automatic fix: TCC (Transparency,
# Consent & Control) is SIP-protected by design — nothing but the user clicking
# in System Settings can add a grant, so a committed script cannot flip one.
# What it does instead is verify every precondition that *is* checkable, name
# the exact subject and pane for the rest, and stop the grants being
# rediscovered from scratch each session.
#
# Two grants matter here, and they are grants to the built products, not to the
# terminal that launches them (issue #380):
#
#   1. Accessibility for OpenSkyUITests-Runner.app, so the runner may drive
#      another process. "Timed out while enabling automation mode" is usually
#      not this grant: it is Automation Mode asking for a password (check 3).
#   2. File access for OpenSky.app. DerivedData/ lives inside the checkout
#      (AGENTS.md), the checkout is on an external volume, so macOS treats the
#      built app as a binary on a removable volume and asks before it may read
#      the game install.
#
# Both are keyed to a code signature, so both stick only while the signature is
# stable. config/Build/Signing.xcconfig names one Apple Development identity for every
# target for exactly this reason; an ad-hoc signature is a new application on
# every build and re-asks forever. That is the one half of this the script can
# check outright, and it does.
set -eu

root="$(cd "$(dirname "$0")/.." && pwd)"
data_root="${OPENSKY_DATA_ROOT:-/Volumes/data/steam/steamapps/common/Skyrim Special Edition}"
derived_data="${OPENSKY_DERIVED_DATA:-$root/DerivedData}"
products="$derived_data/Build/Products/Debug"
status=0

echo "[INFO] checking test permission prerequisites"
echo "       data root:    $data_root"
echo "       build products: $products"
echo

# 1. Data-root readability. Checked directly, because a real-data test host that
#    cannot see the install parks in open() rather than failing.
if [ -e "$data_root/Data/Skyrim.esm" ] || [ -e "$data_root/Skyrim.esm" ]; then
    echo "[ OK ] Skyrim.esm is readable from this shell."
else
    echo "[WARNING] cannot see Skyrim.esm under the data root."
    echo "          Either the path is wrong (set OPENSKY_DATA_ROOT) or this"
    echo "          process lacks access to the volume."
    status=1
fi

# 2. Signature stability. A grant against an ad-hoc signature cannot persist, so
#    this is the difference between "not yet granted" and "granted but broken".
check_signature() {
    bundle="$1"
    name="$(basename "$bundle")"
    if [ ! -d "$bundle" ]; then
        echo "[INFO] $name not built yet — run make build-app or make test-ui first."
        return 0
    fi
    authority="$(codesign -dv --verbose=2 "$bundle" 2>&1 \
        | sed -n 's/^Authority=//p' | head -1)"
    if [ -z "$authority" ]; then
        echo "[ERROR] $name is ad-hoc signed; no TCC grant against it can persist."
        echo "        config/Build/Signing.xcconfig should name an Apple Development identity."
        status=1
    else
        echo "[ OK ] $name is signed by: $authority"
    fi
}

check_signature "$products/OpenSky.app"
check_signature "$products/OpenSkyUITests-Runner.app"

# 3. Automation Mode. XCTest turns it on at the start of every UI run. When it
#    needs authentication, a password prompt waits and the run fails after 60 s
#    with "Timed out while enabling automation mode".
if automationmodetool 2>&1 | grep -q 'DOES NOT REQUIRE'; then
    echo "[ OK ] Automation Mode needs no authentication."
else
    echo "[ERROR] Automation Mode asks for a password on every UI test run."
    echo "        Run once: sudo automationmodetool enable-automationmode-without-authentication"
    status=1
fi

cat <<'MSG'

The two grants themselves live in the root-owned system TCC database, which this
script cannot read without Full Disk Access of its own, so they are listed here
rather than verified. Each is one click, once per signature:

1. Accessibility — lets the UI-test runner drive the app.
   System Settings > Privacy & Security > Accessibility > add:
     OpenSkyUITests-Runner.app   (in DerivedData/Build/Products/Debug)

2. Files and Folders / Full Disk Access — lets the built app read the game
   install on the external volume without a prompt mid-run.
   System Settings > Privacy & Security > Full Disk Access > add:
     OpenSky.app                 (in DerivedData/Build/Products/Debug)

`make test-ui` is the check that matters: it reaches a test case when every
grant above is in place.

Opening the Accessibility pane now...
MSG

open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" \
    2>/dev/null || echo "[INFO] open System Settings > Privacy & Security manually."

exit "$status"

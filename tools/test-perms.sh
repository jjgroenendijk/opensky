#!/bin/sh
# Guide the one-time macOS TCC grants that stop test runs from blocking on
# permission popups (external-volume file access + UI-test automation).
#
# Why this is a helper and not a fully automatic fix: TCC (Transparency,
# Consent & Control) is SIP-protected by design — nothing but the user clicking
# in System Settings can add a grant, so a committed script cannot flip it. What
# this script does is make the grant a single guided step and verify the part it
# can (data-root readability), so it stops being rediscovered every session.
#
# The durable lever: grant Full Disk Access + Automation to the STABLE parent
# process you launch tests from (Terminal / iTerm / Xcode). Child test hosts
# inherit that access. The app itself is ad-hoc signed ("-"), so its identity
# changes every rebuild and per-app grants to it never persist — grant the
# parent, not the app.
set -eu

data_root="${OPENSKY_DATA_ROOT:-/Volumes/data/steam/steamapps/common/Skyrim Special Edition}"

echo "[INFO] checking real-data test prerequisites"
echo "       data root: $data_root"

if [ -e "$data_root/Data/Skyrim.esm" ] || [ -e "$data_root/Skyrim.esm" ]; then
    echo "[ OK ] Skyrim.esm is readable from this shell — file access works here."
else
    echo "[WARNING] cannot see Skyrim.esm under the data root."
    echo "          Either the path is wrong (set OPENSKY_DATA_ROOT) or this"
    echo "          process lacks access to the volume."
fi

# Name the likely controlling app so the instructions are concrete.
parent_app="your terminal app (Terminal / iTerm) and Xcode"
term="${TERM_PROGRAM:-}"
case "$term" in
    Apple_Terminal) parent_app="Terminal (and Xcode, if you run tests from it)" ;;
    iTerm.app) parent_app="iTerm (and Xcode, if you run tests from it)" ;;
    vscode) parent_app="Visual Studio Code (and Xcode, if you run tests from it)" ;;
esac

cat <<MSG

One-time grants that stop the popups (do each once, then they persist):

1. Full Disk Access — lets the test host read the external game volume without
   the "would like to access files on a removable volume" prompt.
   System Settings > Privacy & Security > Full Disk Access > add:
     $parent_app

2. Automation / Accessibility — lets UI tests drive the app without the
   "enabling automation mode" timeout (make test-ui).
   System Settings > Privacy & Security > Automation (and Accessibility) >
   allow the same app(s) to control the system / OpenSky.

Opening the Full Disk Access pane now (add the app, then re-run your tests)...
MSG

open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles" \
    2>/dev/null || echo "[INFO] open System Settings > Privacy & Security manually."

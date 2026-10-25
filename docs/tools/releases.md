---
type: Tool
title: Releases
description: How OpenSky previews reach GitHub - the nightly preview workflow, the version and
  tag, the disk image, a release by hand, the signing it has and lacks, and what a user does on
  first open.
tags: [tool, release, build]
---

# Releases

A release is a disk image (`.dmg`) of the Release app, attached to a GitHub release. It holds
only our own build. The user's game install is never read or packed.

## Nightly previews

`.github/workflows/preview.yml` publishes a preview every night at 02:41 UTC, and on demand with
`gh workflow run preview.yml`. Its plan job, on Linux, runs `tools/ci/preview-release.sh plan`:

1. Walk `main`'s first-parent history and take the newest commit whose `Lint` check passed. The
   newest commit may have no result, because a later push to `main` cancels the older run.
2. Skip when the last preview of this version already holds that commit, so a quiet night
   publishes nothing.
3. Name the tag `v<MARKETING_VERSION>-preview.<N>`, one above the last preview of that version.

The release title is `Nightly <UTC date>`, such as `Nightly 2026-10-25`. A second preview on
the same day gets `Nightly 2026-10-25 (2)`. GitHub's release list cuts long titles, so the
title starts with the part that differs, and the version stays in the tag.

The newest 20 previews are kept. After it publishes, the script deletes every older pre-release
with a `-preview.<N>` tag, together with its tag. A night without new commits publishes nothing,
so it deletes nothing either. A stable release is never deleted.

The macOS job then checks out that commit, runs `make build-app CONFIG=Release` and `make dmg`,
and publishes a pre-release. The notes are `.github/preview-release-notes.md` followed by
GitHub's list of the pull requests merged since the last preview.

To start a new version, change `MARKETING_VERSION` in `config/Build/Base.xcconfig`. The next
preview is then `v<new version>-preview.1`.

## By hand

1. Build the app from `main`: `make build-app CONFIG=Release`.
2. Pack it: `make dmg NAME=OpenSky-0.1.0-preview.1`. The image lands in `.logs/dmg/<UTC>/`. It
   holds `OpenSky.app` and a shortcut to Applications, so the user drags one onto the other.
3. Publish it as a pre-release on the `main` commit you built:

   ```sh
   gh release create v0.1.0-preview.1 --prerelease --target main \
     --title "Nightly 2026-10-24" --notes-file notes.md .logs/dmg/latest/OpenSky-0.1.0-preview.1.dmg
   ```

A preview tag ends in `-preview.N`. GitHub marks a pre-release so that "latest release" stays
empty until a stable one exists.

## Signing and Gatekeeper

A local build is signed with the "Apple Development" certificate in
`config/Build/Signing.xcconfig`. The CI runner holds no certificate, so a nightly preview is
signed ad hoc (`CODE_SIGN_IDENTITY=-`). Neither is a "Developer ID" certificate, so neither app
can be notarized. Notarization is Apple's malware check that Gatekeeper, the macOS launch
check, asks for.

A browser marks a downloaded file as quarantined, and the app copied out of the image keeps the
mark. Gatekeeper then stops the first open. A zip and a disk image behave the same way. The user
opens System Settings, goes to Privacy & Security, and presses Open Anyway. The README says
this.

To remove that step, the release needs a Developer ID certificate (paid Apple Developer Program)
and a `notarytool submit` plus `stapler staple` step on the image.

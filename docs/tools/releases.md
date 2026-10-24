---
type: Tool
title: Releases
description: How to publish an OpenSky preview on GitHub - the version, the disk image, the
  signing it has and lacks, and what a user does on first open.
tags: [tool, release, build]
---

# Releases

A release is a disk image (`.dmg`) of the Release app, attached to a GitHub release. It holds
only our own build. The user's game install is never read or packed.

## Steps

1. Set `MARKETING_VERSION` in `config/Build/Base.xcconfig`, such as `0.1.0`, and land it on
   `main`.
2. Build the app from `main`: `make build-app CONFIG=Release`.
3. Pack it: `make dmg NAME=OpenSky-0.1.0-preview.1`. The image lands in `.logs/dmg/<UTC>/`. It
   holds `OpenSky.app` and a shortcut to Applications, so the user drags one onto the other.
4. Publish it as a pre-release on the `main` commit you built:

   ```sh
   gh release create v0.1.0-preview.1 --prerelease --target main \
     --title "OpenSky 0.1.0 preview 1" --notes-file notes.md .logs/dmg/latest/OpenSky-0.1.0-preview.1.dmg
   ```

A preview tag ends in `-preview.N`. GitHub marks a pre-release so that "latest release" stays
empty until a stable one exists.

## Signing and Gatekeeper

The app is signed with the "Apple Development" certificate in `config/Build/Signing.xcconfig`.
That is not a "Developer ID" certificate, so the app cannot be notarized. Notarization is
Apple's malware check that Gatekeeper, the macOS launch check, asks for.

A browser marks a downloaded file as quarantined, and the app copied out of the image keeps the
mark. Gatekeeper then stops the first open. A zip and a disk image behave the same way. The user
opens System Settings, goes to Privacy & Security, and presses Open Anyway. The README says
this.

To remove that step, the release needs a Developer ID certificate (paid Apple Developer Program)
and a `notarytool submit` plus `stapler staple` step on the image.

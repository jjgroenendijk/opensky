---
type: Decision
title: Native macOS app, programmatic AppKit, Metal 4 command pipeline
description: Why OpenSky is a macOS-only target with a code-built AppKit shell around MTKView, no
  sandbox, a stable signing identity, and the Metal 4 API family.
tags: [decision, platform, rendering, signing, privacy]
---

# Native macOS app

## Context

The repository started from Xcode's iOS Metal 4 game template (`SDKROOT = iphoneos`, UIKit, a
storyboard). OpenSky targets native macOS 26 and later, and the template also failed strict lint
(force unwraps, force casts, no formatting).

## Decision

- macOS only: `SDKROOT = macosx`, `SUPPORTED_PLATFORMS = macosx`, `MACOSX_DEPLOYMENT_TARGET = 26.0`.
  No Catalyst and no iOS.
- The project format is Xcode 26.3 (`objectVersion = 100`). The mapping, found in Xcode's
  DevToolsCore, is 16.0 to 77, 16.3 to 90, and 26.3 to 100.
- AppKit is built in code: an `@main` enum starts `NSApplication`, the app delegate, and the game
  view controller around an `MTKView`. There is no storyboard or nib, so nothing hides in Interface
  Builder files and everything is reviewable as code.
- There is no `Info.plist` file. `GENERATE_INFOPLIST_FILE = YES` makes it.
- Signing uses one Apple Development identity. macOS ties permission grants, such as consent to
  read a removable volume, to the code signature. An ad-hoc signature changes with every build, so
  macOS would ask again after each build. The details are on the
  [build system](/tools/build-system.md#signing) page.
- `NSRemovableVolumesUsageDescription` explains why OpenSky reads the chosen Skyrim install. The
  first access still needs the user's consent.
- There is no app sandbox. The engine must read the user's install at any path, for example
  `/Volumes/data/steam/...`, and a sandbox would block that.
- The renderer uses the Metal 4 objects: `MTL4CommandQueue`, `MTL4CommandBuffer`,
  `MTL4ArgumentTable`, `MTLResidencySet`, and shared-event frame pacing, with the command flow
  following Apple's template. A GPU without the `.metal4` family gets an on-screen message, not a
  crash.

## Trade-offs

- The Metal 4 API is new and macOS 26 only, so there are fewer references than for classic Metal.
  Accepted, per the Metal 4 only rule in `AGENTS.md`.
- A default local build needs this team's Apple Development certificate. CI and other builders
  without it opt into ad-hoc signing through `XCODEBUILD_FLAGS`.
- Apple Development signing is not distribution signing. Developer ID signing and notarization are
  future work and may give a different designated requirement.
- `swiftformat --importgrouping alphabetized` agrees with SwiftLint's `sorted_imports`, so the two
  tools do not fight.

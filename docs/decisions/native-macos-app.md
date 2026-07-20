---
type: Decision
title: Native macOS app, programmatic AppKit, Metal 4 command pipeline
description: Replaced the iOS Xcode template with a macOS-only target and a
  code-built AppKit shell around MTKView; renderer uses the Metal 4 API family.
tags: [decision, platform, rendering, signing, privacy]
timestamp: 2026-07-20T00:00:00Z
---

# Native macOS app skeleton

## Context

Repo was seeded from Xcode's iOS Metal 4 game template (`SDKROOT = iphoneos`,
UIKit, storyboard). Mission demands native macOS 26+ (AGENTS.md). Template also
failed strict lint (force-unwraps, force-casts, unformatted).

## Decision

* Convert project to macOS-only: `SDKROOT = macosx`, `SUPPORTED_PLATFORMS = macosx`,
  `MACOSX_DEPLOYMENT_TARGET = 26.0`. No Catalyst, no iOS.
* Project format: Xcode 26.3 (`objectVersion = 100`), per user request. Mapping
  discovered from Xcode's DevToolsCore: 16.0 -> 77, 16.3 -> 90, 26.3 -> 100.
* Programmatic AppKit: `@main` enum -> `NSApplication` + `AppDelegate` +
  `GameViewController` (MTKView). No storyboard/nib -> nothing hidden in IB files,
  everything reviewable as code.
* No Info.plist file: `GENERATE_INFOPLIST_FILE = YES` supplies it.
* Local signing: Apple Development, team `92X872A57T`. Stable designated requirement
  lets macOS remember removable-volume consent across app + test rebuilds. Ad-hoc
  signatures identify each rebuild by a new code hash -> repeated consent prompts.
  `make test-ui` keeps its entire isolated build graph ad-hoc: development-signing the
  generated runner makes macOS deny its non-promptable Developer Tool request, while
  mixing an ad-hoc runner with a development-signed app prevents XCTest pairing. UI tests
  use synthetic internal-disk data, so they need no removable-volume consent.
* CI passes `XCODEBUILD_FLAGS='CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM='` through Make ->
  ad-hoc builds remain certificate-free. Other certificate-free environments can use
  the same explicit override.
* `NSRemovableVolumesUsageDescription` explains why OpenSky reads the chosen Skyrim
  install. First access still needs user consent; stable signing makes that consent
  durable across rebuilds.
* No app sandbox: engine must read the user's Skyrim install at an arbitrary path
  (e.g. `/Volumes/data/steam/...`); sandbox would block it.
* Renderer uses Metal 4 objects (`MTL4CommandQueue`, `MTL4CommandBuffer`,
  `MTL4ArgumentTable`, `MTLResidencySet`, shared-event frame pacing), command flow
  adapted from Apple's template. GPU without `.metal4` family -> on-screen message,
  no crash.
* Placeholder scene: rotating vertex-colored triangle. Proves pipeline before any
  game-format work; verified visually on M1 (screenshot via XCUITest probe).

## Trade-offs

* Metal 4 API is new + macOS 26-only -> smaller reference pool than classic Metal;
  accepted per AGENTS.md "Metal 4 only, no shims".
* Default local builds require this team's Apple Development certificate. CI + other
  certificate-free builders must opt into ad-hoc signing through `XCODEBUILD_FLAGS`.
* Apple Development signing is not distribution signing. Developer ID/notarization
  remains future work and may establish a different designated requirement.
* `swiftformat --importgrouping alphabetized` (was testable-bottom) to agree with
  SwiftLint `sorted_imports`; tools must not fight.

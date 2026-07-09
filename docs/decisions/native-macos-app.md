---
type: Decision
title: Native macOS app, programmatic AppKit, Metal 4 command pipeline
description: Replaced the iOS Xcode template with a macOS-only target and a
  code-built AppKit shell around MTKView; renderer uses the Metal 4 API family.
tags: [decision, platform, rendering]
timestamp: 2026-07-09T00:00:00Z
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
* Signing: ad-hoc (`CODE_SIGN_IDENTITY = "-"`), no `DEVELOPMENT_TEAM` -> builds on
  any machine + CI without certificates. Revisit for distribution.
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
* Ad-hoc signing means no TestFlight/notarization path yet — irrelevant now.
* `swiftformat --importgrouping alphabetized` (was testable-bottom) to agree with
  SwiftLint `sorted_imports`; tools must not fight.

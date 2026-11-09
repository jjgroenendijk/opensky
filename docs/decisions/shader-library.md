---
type: Decision
title: The shaders are one package module
description: The Metal shaders compile once, as the OpenSkyShaders package target, into the
  default.metallib of its resource bundle, which the app, the CLI, and every test load.
tags: [decision, metal, build, shaders]
---

# The shaders are one package module

## Decision

The `.metal` files and their headers are the `OpenSkyShaders` module in `src/Package.swift`.
Its build compiles them once into `default.metallib` in the module's resource bundle. The
app, `openskycli`, `swift test`, and every xcodebuild test plan load that file through
`ShaderLibrary.make(device:)`. `ShaderLibrary.url` also stamps the pipeline cache.

Before, the app and the CLI each compiled the shaders into their own bundle, and `make`
compiled them a third time for the package tests, which found the file through an
environment variable that each test plan set.

## What a package Metal compile takes

Measured on 2026-11-09 with Swift 6.4 and Xcode 27.2:

- A `.metal` file in a Swift target compiles into the bundle's `default.metallib` without a
  `resources:` entry. A `.h` file in the folder is not copied into the bundle.
- `swift build` passes `-fmetal-math-mode=fast` by default, the same as `MTL_FAST_MATH`.
- It passes no header search path from `cSettings`, and no `-Werror`. So `ShaderCommon.h`
  includes `../OpenSkyShaderTypes/ShaderTypes.h` by its relative path.
- xcodebuild applies `MTL_FAST_MATH` and `MTL_TREAT_WARNINGS_AS_ERRORS` from
  `Overrides.xcconfig`, which reaches package targets through `XCODE_XCCONFIG_FILE`. So every
  `make build-*` and `make test` fails on a shader warning, and CI runs both. Only
  `make test-package` (`swift test`) prints a shader warning without failing.

## Alternatives rejected

- One library target on the app side that the CLI and the tests load by path. It keeps a
  path that every consumer must know, and `swift test` would still need its own compile.

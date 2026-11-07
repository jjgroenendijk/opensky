---
type: Decision
title: Swift language rules
description: The three Swift language features every target turns on - explicit existential
  types, internal imports by default, and strict memory safety - why, and how the check works.
tags: [decision, swift, compiler, lint, code-quality]
---

# Swift language rules

The compiler enforces three rules on every target: the app, `openskycli`, every package module,
and every test target. Each rule makes a hidden cost or risk visible in the source. The compiler
checks it, so no other tool is needed. Warnings are errors in every target, so a broken rule
fails the build.

| Rule | Feature | Package setting | Xcode build setting |
| --- | --- | --- | --- |
| A protocol used as a type is written `any X` | [SE-0335](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0335-existential-any.md) | `.enableUpcomingFeature("ExistentialAny")` | `SWIFT_UPCOMING_FEATURE_EXISTENTIAL_ANY` |
| An import is `internal` unless it says `public import` | [SE-0409](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0409-access-level-on-imports.md) | `.enableUpcomingFeature("InternalImportsByDefault")` | `SWIFT_UPCOMING_FEATURE_INTERNAL_IMPORTS_BY_DEFAULT` |
| An unsafe pointer or unsafe API use is marked `unsafe` | [SE-0458](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0458-strict-memory-safety.md) | `.strictMemorySafety()` | `SWIFT_STRICT_MEMORY_SAFETY` |

## Why each rule

- **Explicit existential types.** A value of type `any X` is a box. A call on it goes through a
  witness table, and a large value is stored on the heap. A generic parameter or `some X` has
  neither cost. Without the rule, `X` and `any X` look the same in the source, so the cost is
  hidden.
- **Imports do not leak.** Without the rule, `import X` in one file makes `X` part of the
  module's public interface whenever a public declaration uses one of its types. A client then
  depends on `X` without listing it. With the rule, a module re-exports a dependency only
  through an explicit `public import X`. So the public dependencies of a module are the lines
  that say `public import`.
- **Unsafe code is marked.** The format readers, the Metal buffer code, and the ffmpeg and
  astcenc wrappers use unsafe pointers. The `unsafe` keyword marks each such expression, so a
  reviewer finds the interop code with one search, and new unsafe code cannot hide in a safe
  file.

## How the settings stay the same

`Package.swift` lists the features in `languageSettings`, and `config/Build/Base.xcconfig` sets
the matching build settings for the app, the CLI, and the Xcode test bundles.
`tools/lint/language-rules.sh` (`make language-rules`, in `make check` and CI) checks that:

- every required feature is in `languageSettings`;
- every feature in `languageSettings` has its build setting set to `YES` in the xcconfig, and the
  reverse;
- each rule rejects a small violation. The script compiles one short snippet per rule with the
  flags it read from `Package.swift`. A snippet that compiles means the rule is off, and the
  check fails. A clean snippet must compile, so a broken flag cannot pass by rejecting
  everything.

`NonisolatedNonsendingByDefault` and `InferIsolatedConformances` map to one Xcode setting,
`SWIFT_APPROACHABLE_CONCURRENCY`, which turns on both.

## Public imports in interface modules

`make module-graph` rule 11 reads every `public import` in an interface module. It may name a
lower module or another interface module, never a feature implementation. `@_exported import` is
not used anywhere, because it re-exports a module to every client without a `public import`
line that shows it.

## Writing code under the rules

- Write `any X` for a protocol type, or use a generic parameter or `some X` when one concrete
  type is enough.
- Start a file with `import X`. Write `public import X` only when a public declaration of the
  file uses a type of `X`. The compiler names the file and the module when one is missing.
- Mark an unsafe expression with `unsafe`, for example `unsafe pointer.pointee`. Keep the unsafe
  part small: wrap it in a safe function with a typed interface, as the root `AGENTS.md` asks
  for C interop.
- Keep `unsafe` at the start of a statement or right after `=`, `return`, or `{`. Swift rejects it
  to the right of an operator such as `+`, and SwiftFormat 0.64.5 removes the parentheses that
  would group it, and joins `unsafe (` into `unsafe(`. So put the unsafe part in its own `let`:
  `let size = unsafe String(format: "%.1f GiB", gibibytes)`, then use `size`.
- A type that stores an unsafe pointer, such as an ffmpeg context, is marked `@safe` when its
  own API keeps the pointer valid: it allocates in its initializer, frees in `deinit`, and never
  hands the pointer out. Otherwise it is `@unsafe`, and every use of it is marked `unsafe`.
- Metal's types are not `Sendable`, so a file that sends them across isolation writes
  `@preconcurrency @unsafe import Metal`. Strict memory safety asks for `@unsafe` there, because
  `@preconcurrency` turns data-race errors from that module into warnings.

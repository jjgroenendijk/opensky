# AGENTS.md — OpenSky

OpenSky is a clean-room reimplementation of the Skyrim Special Edition engine (Bethesda
Creation Engine, Gamebryo lineage) for macOS in Swift and Metal 4. It loads a user's own,
legally-owned install from disk and runs it. Trade-offs resolve in this order: legal
cleanliness, correctness, native feel, performance, feature completeness.

This file holds what applies to every task. Task-specific workflows live in skills; a
change to repo layout, tooling, or conventions updates this file in the same commit.

## Legal & IP boundary — non-negotiable

Located in Netherlands. EU Software Directive 2009/24/EC (arts. 5-6) and the Dutch
Auteurswet permit reverse-engineering a program you lawfully own for interoperability.
Reversing formats is fine. Redistributing Bethesda content or code is not. Therefore:

- NEVER commit game content. No `.bsa`/`.ba2` archives, `.esm`/`.esp` plugins, `.nif`
  meshes, `.dds` textures, `.hkx` animations, `.pex` scripts, audio, or anything extracted
  from the install. Not even as test fixtures.
- NEVER copy Bethesda code. No decompiled, disassembled, or leaked source. No pasted
  SKSE or Creation Kit internals. Reimplement from observed behavior and open format docs.
- A frame OpenSky renders embeds the user's game assets, so a rendered capture is game
  content too. Verification captures go to gitignored `logs/`; link the local path in the
  PR rather than committing the image.
- The game install is read-only external input: located at runtime, never bundled, cached
  into the repo, or copied into build output.
- About to add a binary blob -> stop, ask.

`make no-game-content` and the pre-commit hook enforce the first and third rules over both
staged files and the whole tracked tree. Nothing enforces the second one; that is on you.

A task that seems to require committing or embedding game data -> do not. Surface the
conflict.

## Gotchas

- The repo sits on a case-insensitive external APFS volume. A case-only rename needs
  `git mv`, and AppleDouble `._*` files are ignored.
- Xcode 26 ships without the Metal Toolchain. `make bootstrap`, once per checkout,
  downloads it.
- Target membership under `Sources/` follows the folder split, not a list in the project
  file: `OpenSky/` builds only into the app, `OpenSkyCLI/` only into the CLI, and
  `Shaders/` into both. Every other folder under `Sources/` is a module of the Swift
  package in `Package.swift`. The app and the CLI link all of them through one product,
  `OpenSkyModules`, so a new module needs no project-file edit (`docs/tools/modules.md`).
  Build through `OpenSky.xcworkspace`, which holds both, as `make` does. An app-only source
  (importing AppKit, Cocoa, or SwiftUI) belongs under `OpenSky/`; anywhere else it breaks
  the CLI build. `make cli-boundary` catches this.
- A folder that builds a target has the target's name, in PascalCase: `Sources/OpenSky/`
  builds `OpenSky`, `Tests/OpenSkyTests/` builds `OpenSkyTests`. A test selector names the
  target: `make test-fast T='OpenSkyFormatsCoreTests/BSAArchiveTests'`. Two names stay lowercase on
  purpose: the CLI binary is `openskycli`, as terminal commands usually are, and the
  bundle IDs keep their old form, because macOS stores permission grants against them.
- The build cache is `DerivedData/` inside the checkout, not the Xcode default under
  `$HOME`: this project's cache runs to tens of gigabytes and the boot volume is small
  enough that the default location fills it mid-session. `make` passes `-derivedDataPath`
  on every `xcodebuild` call and exports `OPENSKY_DERIVED_DATA` for the scripts under
  `tools/`, so a new build command has to pass it too or it will silently start a second
  cache on the boot disk. Override with `make DERIVED_DATA=... <target>`.
- Git hooks are the gate — never `--no-verify`.
- Linked worktrees share the main checkout's `.vendor/ffmpeg` and compilation cache
  automatically through `make`, so `make bootstrap` is not needed per worktree and a fresh
  worktree's first build reuses what others compiled. The cache's prefix mapping makes
  `#filePath` read `/^src/...`: find the checkout at runtime instead
  (`docs/tools/build-system.md`).
- Facts about this machine and the outside world that will expire — CI status, missing TCC
  permissions, blocked upstream spec hosts — live in `docs/tools/environment.md` with the
  date each was observed. Record them there, never inline here or in a skill.

## Environment & tech stack

- Metal 4 only. No OpenGL, no MoltenVK, no abstraction layer over another API.
- macOS 26+ (Tahoe), Xcode 26, Apple Silicon. No older-macOS or Intel paths unless asked.
- Minimal C interop, only where a format genuinely needs it, wrapped behind a Swift
  interface. No embedded game engine.
- Dependencies: prefer the standard library and Apple frameworks, then Swift Packages via
  SwiftPM. Record each new dependency and the reason in `docs/decisions/`; its license must
  stay compatible with redistributing our code.

## Where things live

The repo root holds only this document, `Makefile`, the Xcode project and the workspace
that holds it beside `Package.swift`, `Config/`, `Sources/`, `Tests/`, `docs/`, `tools/`, and dotfiles.

```text
Config/
  Build/                *.xcconfig, every build setting
  TestPlans/            *.xctestplan, which bundles a run touches
Sources/
  OpenSky/              OpenSky (app) only: Shell/, Panels/, GameView/, Resources/
  OpenSkyCLI/           OpenSkyCLI only: Commands/, SWF/, Support/
  Shaders/              OpenSky and OpenSkyCLI: Shaders.metal
  OpenSkyEngine/        package module: the engine not yet split, one folder per domain
  OpenSkyFormatsCore/   package module: binary readers, compression, geometry, BSA, strings
  OpenSkyFormats*/      package modules, one per format family: ESM, Mesh, Animation, Audio,
                        PEX, SWF; one folder per format inside
  OpenSkyGameData/      package module: virtual file system, load order, record stores
  OpenSkyBehavior/      package module: behavior graph evaluation, skeleton pose math
  OpenSkyDiagnostics/   package module: memory footprint, debug world overlays
  OpenSkyPhysics/       package module: collision worlds, dynamic bodies, ragdolls
  OpenSkyRendering/     package module: Metal renderer, scenes, cameras, terrain meshes
  OpenSkyAudio/         package module: audio graph, decoders, sound and music stores
  OpenSkyWorldState/    package module: runtime state store, components, clock, globals
  OpenSkyConditions/    package module: condition evaluator and function registry
  OpenSkyPerception*/   feature module: perception runtime; Interface: detection values
  OpenSkyShaderTypes/   package module: the clang module wrapping ShaderTypes.h
  CFFmpeg/              package module: the clang module over the vendored ffmpeg
Tests/
  OpenSkyTests/         synthetic unit suites for the app and engine
  OpenSkyFormats*Tests/ package test targets: synthetic suites, one per format module
  OpenSkyGameDataTests/ package test target: synthetic suites for OpenSkyGameData
  OpenSkyBehaviorTests/ package test target: synthetic suites for OpenSkyBehavior
  OpenSkyPhysicsTests/  package test target: synthetic suites for OpenSkyPhysics
  OpenSkyRenderingTests/ package test target: synthetic suites for OpenSkyRendering
  OpenSkyAudioTests/    package test target: synthetic suites for OpenSkyAudio
  OpenSkyWorldStateTests/ package test target: synthetic suites for OpenSkyWorldState
  OpenSkyPerceptionTests/ package test target: synthetic suites for OpenSkyPerception
  OpenSkyRealDataTests/ env-gated suites that read the user's install
  TestSupport/          fixtures OpenSkyTests and OpenSkyRealDataTests compile; not a target
  Formats*Testing/      package libraries: byte-building fixtures, one per format module
  BehaviorTesting/      package library: behavior graph fixtures
  PhysicsTesting/       package library: collision scene and ragdoll fixtures
  OpenSkyPerceptionTesting/ package library: perception world fake and fixtures
  OpenSkyUITests/       XCUITest smoke tests
```

Every build setting lives in `Config/Build/*.xcconfig`, not in the pbxproj, signing
included: `Config/Build/Signing.xcconfig` names one Apple Development identity for every
target, because macOS ties permission grants to the code signature and ad-hoc signing
re-asks on every build (`docs/tools/build-system.md`). `Config/TestPlans/` holds the four
checked-in test plans, for the same reason: which bundles a run touches is reviewable
configuration, not a flag. `UnitTests.xctestplan` lists `OpenSkyTests` and the package test targets,
`UITests.xctestplan` lists `OpenSkyUITests` alone, and `RealData.xctestplan` lists
`OpenSkyRealDataTests` alone and carries the data root into the test host — no plan lists
the UI bundle beside an app-hosted unit bundle, because such a bundle deadlocks the UI
runner it shares a session with (`docs/testing.md`). A gated suite written outside
`Tests/OpenSkyRealDataTests/` fails `make lint`, because nothing would ever run it.

No Swift file sits loose at the root of `Sources/OpenSky/`, `Sources/OpenSkyEngine/`,
`Sources/OpenSkyFormats*/`, or `Sources/OpenSkyEngine/World/`; each goes in a domain folder.
`Sources/OpenSkyGameData/` is small enough to stay flat. `Sources/OpenSkyRendering/` keeps the
renderer at its root and puts `UI/`, `Terrain/`, and `Weather/` in folders. The others:

- `Sources/OpenSky/`: `Shell/` (app lifecycle, sidebar, panel framework), `Panels/` (one
  view controller per destination), `GameView/` (`GameViewController` and its extensions),
  and `Resources/` (`Assets.xcassets`, `Branding/`).
- `Sources/OpenSkyEngine/`: one folder per domain (`Magic/`, `Dialogue/`, `Quests/`,
  ...). A panel seam, `XControlProviding.swift` or `XReadout.swift`, lives in its domain
  folder.
- `Sources/OpenSkyFormats*/`: one folder per format (`BSA/`, `ESM/`, `NIF/`, ...), plus
  `Binary/`, `Compression/`, and `Geometry/`. A package module never imports a module above
  it; behavior that needs a higher layer goes in an extension file up there
  (`docs/tools/modules.md`).
- `Sources/OpenSkyEngine/World/`: `Actors/`, `Cells/`, `Conditions/`,
  `Navigation/`, `Packages/`, `Player/`, `State/`, `Streaming/`, `Terrain/`, and `Weather/`.
- `Sources/OpenSkyCLI/`: `OpenSkyCLI.swift` (dispatch) and `OpenSkyCLIUsage.swift` at the
  root, one file per subcommand in `Commands/`, the Flash (SWF) probes in `SWF/`, and
  shared plumbing in `Support/`.

An extension file is named `Type+Feature.swift`, for example
`GameView/GameViewController+Magic.swift`. Test folders use the same subfolder names as the
source file they test: the tests for
`Sources/OpenSkyEngine/World/Terrain/DistantLOD.swift` live in
`Tests/OpenSkyTests/World/Terrain/`, and tests for app code live under `Tests/OpenSkyTests/App/`. Only
cross-cutting folders are test-only: `Acceptance/` (milestone gates), `Fakes/`, and
`Support/`. File names stay unique inside a target, because Swift rejects two files with
one name in the same module. Skills live in `.AGENTS/skills/` (`.claude/skills` symlinks
there). `logs/` and `.vendor/` are gitignored. `docs/` groups pages by folder: `formats/`,
`engine/`, `rendering/`, `decisions/`, and `tools/`.

Run output is per-run, not per-name: a script that writes a transcript, a capture, or a
result bundle puts it in `logs/<script>/<UTC timestamp>/` (or the same shape under
`DerivedData/TestResults/`) through `tools/run-dir.sh`, prints that directory, and points
`latest` at it. Link the run directory, never a loose file. `make prune` deletes stale
worktree `DerivedData/` and aged-out runs; `docs/tools/run-output.md` has the rules.

## Build, run, test

`make help` lists every target. `make fix` (autoformat plus strict lint) before committing;
`make check` is the same gate without writes. `make install` refreshes
`/Applications/OpenSky.app` after landing rendering work.

No hook runs the tests: what to test and verify for a change is the author's judgment,
guided by the `testing-and-verifying` skill, and recorded in the commit's `Tests:` section.
A green build does not prove a triangle appeared. Unit-test every format parser and math
routine, with synthetic fixtures built in code. `make test` and `make test-fast` never run
the env-gated real-data suites, which need the user's install; `make realtest` and
`make realtest-all` do, and none of them can run in CI.

## Loading game data (runtime, never repo)

The default path to probe is
`~/Library/Application Support/Steam/steamapps/common/Skyrim Special Edition/`; on this
machine the data lives under `/Volumes/data/steam/steamapps/...`. The data root is a
configurable setting, never a hardcoded constant. Missing -> fail loud. There is no bundled
data to fall back to.

## Roadmap and open work — GitHub, not docs/

Open work lives in GitHub issues and milestones. There is no roadmap file in the repo, so a
fresh session picks up from `gh`, not from a doc snapshot.

- GitHub milestone `#n` **is** OpenSky milestone `Mn`. Each issue is one numbered roadmap
  item (`9.1.2 .xwm framing parser`) and carries its own acceptance gate; the milestone
  description carries the goal, spec references, and legal notes.
- Start work with `gh issue list --milestone "M9 - audio"`, take the topmost open item, and
  use one branch and one PR per issue, closed from the PR body with `Closes #NNN`.
- Labels: `roadmap`, `acceptance-gate`, `format-parser`, `app-ui`.
- Closed milestones are not empty — every merged PR is assigned to the milestone it landed
  under, so `gh pr list --state merged --milestone "M4 - walkable world"` shows how a
  finished milestone was actually built. Project history lives in git, merged PRs, and
  closed issues, never in `docs/`.
- The `OpenSky roadmap` project board
  (<https://github.com/users/jjgroenendijk/projects/7>) is a view across milestones, not
  the source of truth. Live branch and PR state comes from `gh pr list` and `git log`.
- Milestone done -> record the outcome in the GitHub milestone description or the closing
  PR, then close the milestone. Scope changes are issue edits, not doc edits.

## Documentation wiki — docs/

Docs hold only what the code cannot show: where a fact comes from, why a design was chosen,
where OpenSky differs from the original game, how subsystems work together, and how to use
the tools. Code documents itself through names, types, and short doc comments. History
lives in git, so a page carries no issue numbers, milestones, acceptance records, test
lists, or timestamps. A page stays at 400 lines or fewer (`make docs-length`); split a longer
one by topic. A change that alters one of those facts updates `docs/` in the same commit.
Load the `writing-wiki-docs` skill before writing there.

## Main-app verification surface

Every new subsystem or user-verifiable behavior adds or extends a discoverable option in the
main app sidebar in the same milestone, and the sidebar path must let a user select, force,
toggle, or inspect the behavior without knowing a CLI command. Prefer controls under an
existing destination over a new top-level item.

Parser, math, and infrastructure-only items may defer UI until their first visible consumer;
if their output is useful alone, expose it in the Asset Browser or an inspector.

Every milestone acceptance writes one record, in the format defined by
`docs/tools/sidebar-acceptance.md`, into the PR or issue that closes the milestone. The
record is mandatory and the deterministic tests are its evidence. The record adds to unit
tests, probes, and benchmarks; it does not replace them.

## Code quality

If a machine can check a rule, do not rely on people remembering it. Every language has both
a linter and an auto-formatter, configured under `tools/`; never hand-format.

Linting is strict and warnings are errors. Do not disable or downgrade a rule to pass — fix
the issue. Inline suppression is a last resort and needs a specific rule code plus a
why-comment. No force-unwrap, force-try, or force-cast on data from external files.

Size to the lint limits while writing rather than after a failed `make fix`, which is the
top recurring time sink. Read the thresholds from `tools/lint/.swiftlint.yml` rather than
from a copy in prose; rules absent from that file run at SwiftLint defaults. Past the file
cap, split into a satellite file (`Renderer.swift` -> `RendererScenePass.swift`), noting
which members need same-file `private(set)` access before moving them. Past the parameter or
tuple cap, introduce a struct.

## Conventions

- Swift-to-Metal shared structs go in `Sources/OpenSkyShaderTypes/ShaderTypes.h`
  with explicit `simd`-aligned layout. Swift reaches them through the clang module that
  wraps the header: a file that uses one writes `import OpenSkyShaderTypes`. There is no
  bridging header, so the types are not implicitly visible. Metal shaders keep writing
  `#import "ShaderTypes.h"`.
- Every target is in Swift 6 language mode on Apple Swift 6.3.3 or newer;
  `make swift-baseline` enforces both and `docs/tools/swift-toolchain.md` explains the
  isolation patterns to reach for. Do not build with a `SWIFT_VERSION` override.
- With `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, extensions of a `nonisolated` type
  must also be declared `nonisolated extension` unless the extension deliberately names a
  global actor. The type's isolation does not carry into a separately declared extension.
  Isolation is per declaration, not per file: a `private` helper below a `nonisolated`
  type is main-actor isolated until it says otherwise.
- A declaration in a package module that other modules use is `public`. A struct another
  module builds needs an explicit `public init(...)`, because the implicit memberwise one
  stays internal, and a public value type states `Sendable` itself, because Swift does not
  infer it across a module boundary. Every file that uses a module writes its own
  `import`; tests write `@testable import`. New modules and their dependencies go in
  `Package.swift`, never in the project file.
- `throws` plus typed errors for parse and load failures; malformed input must not crash.
- Anything repeatable becomes a `make` target or a git hook, never a documented manual
  procedure. Local hooks and CI mirror each other, so changing one gate changes both — keep
  `ci.yml` in sync whether or not CI is currently running.

## Writing style (agent output, docs, comments, commit bodies)

Write for young, capable students who learn English as a second language: short
sentences with one idea each, common words, and a technical term explained the first time
it appears. No aphorisms, idioms, clever phrases, filler, or hedging. Prefer an example to a
long explanation.

- Never abbreviate code symbols, function names, API names, or error strings. Quote them
  verbatim.
- No emojis anywhere. Where a severity marker is needed use bracket tags: `[ERROR]`,
  `[WARNING]`, `[INFO]`. Headings are unnumbered.

## How agents work here

- Do not invent Skyrim internals from memory. Training data is confidently wrong about byte
  layouts; confirm against an open spec or observed data, and flag uncertainty.
- A performance idea, or a pre-existing performance problem spotted mid-task, becomes a
  GitHub issue (`gh issue create`) rather than an inline fix. One issue per idea; the title
  states the win, the body states where and why.
- Commits carry no AI or co-author attribution trailers. The commit-msg hook enforces this.
- Anything that builds goes in a background shell, never a foreground call that can hit
  the tool timeout, and never a synchronous `until grep` poll of a log. One xcodebuild per
  derived-data tree at a time (two deadlock), and `git push` builds too.

## Skills — load before the matching work

Each skill in `.AGENTS/skills/` holds the full workflow for one kind of task. Load the
matching one before starting that work rather than reconstructing the rules here.

| Skill | Load it when |
| --- | --- |
| `committing-and-landing-work` | Committing, pushing, or opening and merging a pull request |
| `implementing-format-parsers` | Adding or changing any parser for ESM records, BSA, NIF, DDS, or LOD data |
| `writing-wiki-docs` | Adding or materially changing anything under `docs/` |
| `probing-real-game-data` | Running engine code against the real Skyrim SE install |
| `building-app-ui` | Adding or changing main-app UI — sidebar destinations, control panels, inspectors |
| `testing-and-verifying` | Running any test, build check, or verification, and before pushing |

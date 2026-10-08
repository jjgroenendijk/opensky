# AGENTS.md — OpenSky

OpenSky is a clean-room reimplementation of the Skyrim Special Edition engine (Bethesda
Creation Engine, Gamebryo lineage) for macOS in Swift and Metal 4. It loads a user's own,
legally-owned install from disk and runs it. Trade-offs resolve in this order: legal
cleanliness, correctness, native feel, performance, feature completeness.

This file holds what applies to every task. Rules for one part of the tree live in the
`AGENTS.md` of that folder (`Sources/`, `Tests/`, and some below them), and they load when
you work there. Task workflows live in skills. A change to repo layout, tooling, or
conventions updates the matching file in the same commit.

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
  content too. Verification captures go to gitignored `.logs/`; link the local path in the
  PR rather than committing the image.
- The game install is read-only external input: located at runtime, never bundled, cached
  into the repo, or copied into build output.
- About to add a binary blob -> stop, ask.

`make no-game-content` (part of `make check` and CI) enforces the first and third rules over
the whole tracked tree. Nothing enforces the second one; that is on you.

A task that seems to require committing or embedding game data -> do not. Surface the
conflict.

## Gotchas

- The repo sits on a case-insensitive external APFS volume. A case-only rename needs
  `git mv`, and AppleDouble `._*` files are ignored.
- Xcode 26 and 27 ship without the Metal Toolchain. `make bootstrap`, once per checkout,
  downloads it.
- Target membership under `Sources/` follows the folder, not a list in the project file:
  `OpenSky/` builds only into the app, `OpenSkyCLI/` only into the CLI, and `Shaders/` into
  both. Every other folder is a module in `Package.swift`, linked by the app and the CLI
  through one product, so a new module needs no project-file edit. An app-only source
  (AppKit, Cocoa, SwiftUI) outside `OpenSky/` breaks the CLI build; `make cli-boundary`
  catches it.
- A folder that builds a target has the target's name, in PascalCase. A test selector names
  the target: `make test-unit T='OpenSkyFormatsCoreTests/BSAArchiveTests'`. Two names stay
  lowercase on purpose: the CLI binary `openskycli`, and the bundle IDs, because macOS
  stores permission grants against them.
- The build cache is one tree per checkout under `~/Library/Caches/OpenSky/`, on the fast
  internal disk; the compilation cache store they all share stays on the data volume.
  `make` passes both on every `xcodebuild` call and exports `OPENSKY_DERIVED_DATA` for
  `tools/`. A new build command that skips them starts a second, cold cache.
- Anything that builds runs in a background shell: it can pass the tool timeout. One build
  runs at a time on the machine: `make` waits for the build lock and says whose build it
  waits for. `git push` builds too.
- Linked worktrees share the main checkout's `.vendor/ffmpeg` through `make`, so a worktree
  needs no `make bootstrap`. The cache's prefix mapping makes `#filePath` read
  `/^src/...`; find the checkout at runtime instead (`docs/tools/build-system.md`).
- No git hook runs on commit or push. Run `make check` before committing. The CI lint jobs
  on each pull request are the gate before code lands.
- Facts about this machine and the outside world that will expire — CI status, missing TCC
  permissions, blocked upstream spec hosts — live in `docs/tools/environment.md` with the
  date observed. Check it before fighting an odd failure, and record new ones there.

## Environment & tech stack

- Metal 4 only. No OpenGL, no MoltenVK, no abstraction layer over another API.
- macOS 26+ (Tahoe) as the deployment target, Xcode 27, Apple Silicon. No older-macOS or
  Intel paths unless asked.
- Swift 6 language mode. Local builds and CI use the same Apple Swift, 6.4
  (`make swift-baseline`).
- Minimal C interop, only where a format genuinely needs it, wrapped behind a Swift
  interface. No embedded game engine.
- Dependencies: prefer the standard library and Apple frameworks, then Swift Packages via
  SwiftPM. Record each new dependency and the reason in `docs/decisions/`; its license must
  stay compatible with redistributing our code.

## Where things live

- `Package.swift` declares every engine module. `docs/tools/modules.md` lists each one with
  its layer and gives the import rules. Read it before you add a module or an import.
- `Config/Build/*.xcconfig` holds every build setting, signing included, never the pbxproj
  (`docs/tools/build-system.md`). `Config/TestPlans/` holds the test plans
  (`docs/tools/test-runs.md`).
- `.logs/` and `.vendor/` are gitignored. A script writes its output into
  `.logs/<script>/<UTC timestamp>/` through `tools/run-dir.sh` and points `latest` at it.
  Link the run directory, never a loose file (`docs/tools/run-output.md`).
- Skills live in `.AGENTS/skills/`; `.claude/skills` is a symlink to it. Each nested
  `AGENTS.md` has a `CLAUDE.md` symlink beside it; `make lint` checks it.

## Architecture

OpenSky follows six architecture styles. `docs/engine/architecture.md` explains each one,
with an example. When you add code:

- A feature uses another feature only through its `Interface` module. `make module-graph`
  checks this (`docs/decisions/modular-architecture.md`).
- Parsers and game rules are pure: values in, values out. Files, clocks, Metal, audio, and
  UI stay in a thin shell around them.
- Reach the outside world through a protocol (a port), such as `CombatDataProviding` or
  `RenderFrameDriver`, so a test can pass a fake.
- Game logic goes in a coordinator in its feature module, not in `GameViewController`.
- Change a data layout for speed only after a measurement shows the cost.
- Simulation runs on the main actor, in a fixed order and without `await`. Reading and
  decoding a file runs off it, and the frame drains the result. Do not add a new
  `@unchecked Sendable` class, `DispatchQueue`, or `Task.detached`.
  `docs/decisions/concurrency.md` has the rules.

## Build, run, test

`make help` lists the main targets; `make help ALL=1` lists every one. `make fix` (autoformat
plus strict lint) before committing; `make check` is the same gate without writes. Both lint
the Swift files the branch changed; `ALL=1` lints every file. `make install` refreshes
`/Applications/OpenSky.app` after landing rendering work, because the user checks progress
there.

Every build or test run costs minutes, so make every edit a change needs, then run one
check, and fix everything it reports at once. CI runs the whole unit plan on every push to a
pull request; locally, run the smallest plan that covers the change (`testing-and-verifying`
skill) and record it in the commit's `Tests:` section. A green build does not prove a
triangle appeared. Unit-test every format parser and math routine with synthetic fixtures
built in code. The real-data suites need the user's install, so only `make test-real` runs
them, and never in CI.

## Loading game data (runtime, never repo)

The default path to probe is
`~/Library/Application Support/Steam/steamapps/common/Skyrim Special Edition/`; on this
machine the data lives under `/Volumes/data/steam/steamapps/...`. The data root is a
configurable setting, never a hardcoded constant. Missing -> fail loud. There is no bundled
data to fall back to.

## Open work, docs, and the app sidebar

- Open work lives in GitHub issues and milestones; there is no roadmap file. Load the
  `starting-roadmap-work` skill to pick up or finish an item.
- `docs/` holds only what the code cannot show: sources of facts, design reasons, where
  OpenSky differs from the game, how subsystems work together, and tool usage. History
  lives in git. Load `writing-wiki-docs` before writing there.
- Every new subsystem or user-verifiable behavior gets a control in the main app sidebar in
  the same milestone. A user must be able to select, force, toggle, or inspect it without a
  CLI command. Parser, math, and infrastructure-only work may wait for its first visible
  consumer. `building-app-ui` has the placement rules and the acceptance record.

## Code quality

If a machine can check a rule, a machine checks it; do not rely on people remembering it.
Every language has a linter and an auto-formatter, configured under `tools/`; do not
hand-format. Anything repeatable becomes a `make` target, not a documented manual
procedure. `make check` and `ci.yml` mirror each other, so a change to one gate changes
both.

Linting is strict and warnings are errors. Fix the issue rather than disabling or
downgrading a rule: `make lint` fails on any suppression comment, on duplicated Swift, and
on a comment block over 6 lines, with no baseline file
(`docs/decisions/code-health-automation.md`). Parse and load failures use `throws` with typed
errors, and malformed input must not crash: no force-unwrap, force-try, or force-cast on data
from external files. `make health` (unused code) runs in the weekly CI workflow and once in a
milestone's closing PR, not per change.

Size code to the lint limits while writing, not after a failed `make fix`; that has been
the top recurring time sink. The thresholds are in `tools/lint/.swiftlint.yml`, and rules
absent from it run at SwiftLint defaults.

## Writing style (agent output, docs, comments, commit bodies)

Write for young, capable students who learn English as a second language: short
sentences with one idea each, common words, and a technical term explained the first time
it appears. No aphorisms, idioms, clever phrases, filler, or hedging. Prefer an example to a
long explanation. Keep code comments short.

- Quote code symbols, function names, API names, and error strings verbatim. Do not
  abbreviate them.
- No emojis. Where a severity marker is needed use bracket tags: `[ERROR]`, `[WARNING]`,
  `[INFO]`. Headings are unnumbered.
- British spelling: "colour", "behaviour", "optimise". New names in our code follow it too.
  Names from Apple APIs, Havok, and the game keep their own spelling (`NSColor`).

Code documents itself through names and types. A comment holds only the why that the code
cannot show. `docs/` holds only what neither the code nor a short comment can hold, such as
sources, measurements, and cross-subsystem design. Code that needs a what-comment gets a
better name instead.

- A doc comment on a declaration is at most about 3 lines.
- A format fact gets one line plus a link to its `docs/formats/` page, which holds the detail.
- No history ("was", "used to", issue numbers) and no restating of the type or parameter
  names; git and the signature already hold them.

```swift
// Bad: restates the code and tells history.
/// The damage multiplier. A `Float`. Was a `Double` before #412.
// Good: says why.
/// Sneak attacks skip armor, so this applies after the armor step.
```

## How agents work here

- Confirm Skyrim internals against an open spec or observed data, and flag uncertainty.
  Training data is confidently wrong about byte layouts.
- A performance idea, or a performance problem spotted mid-task, becomes a GitHub issue
  (`gh issue create`) rather than an inline fix. One issue per idea; the title states the
  win, the body states why it can be faster. No measurement is needed to file it.
- A pre-existing bug found mid-task, one the current change did not cause, becomes a GitHub
  issue with the `bug` label (`gh issue create --label bug`). One issue per bug; the body
  states how to reproduce it, what was observed, and what is expected. This keeps the bug from
  being lost and keeps the fix out of an unrelated PR. Fix it inline only when it blocks
  the task, and say so in the commit.
- An issue body states intent, not code locations: no file paths, line numbers, or pasted
  code. Code moves faster than issues are worked. `starting-roadmap-work` has the rules.
- Do the whole task in the main session. Do not split work across sub-agents: parallel
  agents have edited the same worktree and collided.

## Skills — load before the matching work

Each skill in `.AGENTS/skills/` holds the full workflow for one kind of task. Each skill
folder also holds `evals.json`: test scenarios to run in a fresh session after you change
the skill.

| Skill | Load it when |
| --- | --- |
| `starting-roadmap-work` | Choosing the next item, starting an issue, or closing a milestone |
| `committing-and-landing-work` | Committing, pushing, or opening and merging a pull request |
| `implementing-format-parsers` | Adding or changing any file format parser: ESM, BSA, NIF, DDS, HKX, PEX, SWF, audio, or LOD |
| `writing-wiki-docs` | Adding or materially changing anything under `docs/` |
| `probing-real-game-data` | Running engine code against the real Skyrim SE install |
| `driving-the-running-game` | Playing, testing, or debugging the live app window through `openskycli game` |
| `building-app-ui` | Adding or changing main-app UI — sidebar destinations, control panels, inspectors |
| `testing-and-verifying` | Running any test, build check, or verification, and before pushing |
| `writing-agent-instructions` | Adding, editing, or reviewing an `AGENTS.md`, skill, or memory, or learning a new rule |

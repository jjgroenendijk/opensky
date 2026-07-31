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
- Filesystem-synced groups add every new file under `opensky/` to every target, so an
  app-only source (importing AppKit, Cocoa, or SwiftUI) needs a `membershipExceptions`
  entry excluding it from `openskycli`. `make cli-boundary` catches this.
- Git hooks are the gate — never `--no-verify`.
- Linked worktrees share the main checkout's `.vendor/ffmpeg` automatically through `make`,
  so `make bootstrap` is not needed per worktree.
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

The repo root holds only this document, `Makefile`, the Xcode project, and dotfiles. Group
engine subsystems under `opensky/` by domain, and keep format parsers separate from
rendering. Skills live in `.AGENTS/skills/` (`.claude/skills` symlinks there). `logs/` and
`.vendor/` are gitignored. `docs/index.md` maps the wiki — trust it over globbing.

## Build, run, test

`make help` lists every target. `make fix` (autoformat plus strict lint) before committing;
`make check` is the same gate without writes. `make install` refreshes
`/Applications/opensky.app` after landing rendering work.

A green build does not prove a triangle appeared. Confirm rendering work by driving the app
or an offscreen render. Unit-test every format parser and math routine, with synthetic
fixtures built in code. Every pushed commit is green.

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
  finished milestone was actually built. Narrative history stays in `docs/log.md`.
- The `OpenSky roadmap` project board
  (<https://github.com/users/jjgroenendijk/projects/7>) is a view across milestones, not
  the source of truth. Live branch and PR state comes from `gh pr list` and `git log`.
- Milestone done -> close the GitHub milestone and record the outcome in `docs/log.md`.
  Scope changes are issue edits, not doc edits.

## Documentation wiki — docs/

`docs/index.md` is the map. A change that adds or alters a subsystem, parser, or non-obvious
decision updates `docs/` in the same commit, `docs/log.md` and `docs/index.md` included.
Load the `writing-wiki-docs` skill before writing there.

## Main-app verification surface

Every new subsystem or user-verifiable behavior adds or extends a discoverable option in the
main app sidebar in the same milestone, and the sidebar path must let a user select, force,
toggle, or inspect the behavior without knowing a CLI command. Prefer controls under an
existing destination over a new top-level item.

Parser, math, and infrastructure-only items may defer UI until their first visible consumer;
if their output is useful alone, expose it in the Asset Browser or an inspector.

Every milestone acceptance writes one record in the format and ledger defined by
`docs/tools/sidebar-acceptance.md`. The record is mandatory and the deterministic tests are
its evidence. This supplements unit tests, probes, and benchmarks; it does not replace them.

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

- Swift-to-Metal shared structs go in `ShaderTypes.h` with explicit `simd`-aligned layout.
- `throws` plus typed errors for parse and load failures; malformed input must not crash.
- Anything repeatable becomes a `make` target or a git hook, never a documented manual
  procedure. Local hooks and CI mirror each other, so changing one gate changes both — keep
  `ci.yml` in sync whether or not CI is currently running.

## Writing style (agent output, docs, comments, commit bodies)

Write normal, clear prose: complete sentences, plain words over jargon, no filler or
hedging. Optimize for the reader, not for brevity.

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
| `delegating-to-subagents` | Splitting a task across parallel or sequential sub-agents |

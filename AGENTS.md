# AGENTS.md — OpenSky

OpenSky is a clean-room reimplementation of the Skyrim Special Edition engine (Bethesda
Creation Engine, Gamebryo lineage) for macOS in Swift and Metal 4. It loads a user's own,
legally-owned install from disk and runs it. Trade-offs resolve in this order: legal
cleanliness, correctness, native feel, performance, feature completeness.

This file holds what applies to every task; a folder's `AGENTS.md` holds its own rules, and
skills hold the workflows. A rule a machine checks is one line naming its gate
(`docs/tools/agent-instructions.md`). A change to layout, tooling, or conventions updates the
matching file in the same commit.

## Legal & IP boundary — non-negotiable

Located in the Netherlands. EU Software Directive 2009/24/EC (arts. 5-6) and the Dutch
Auteurswet permit reverse-engineering a program you lawfully own for interoperability.
Reversing formats is fine. Redistributing Bethesda content or code is not. Therefore:

- NEVER commit game content: no archive, plugin, mesh, texture, animation, script, audio, or
  anything extracted from the install, not even as a test fixture.
- NEVER copy Bethesda code: no decompiled, disassembled, or leaked source, and no code,
  offsets, layouts, or binary class names from SKSE, CommonLibSSE, or other projects built on
  the game binary. Their facts and behaviour are fine through the clean-room read in the
  `using-outside-sources` skill. No gate can check this; it is on you.
- A rendered frame embeds the user's assets, so a capture is game content: it goes to `.logs/`.
  The exception is a launcher screenshot with no game frame, `docs/images/launcher-*.png`.
- The game install is read-only input: located at runtime, never bundled, cached into the
  repo, or copied into build output.
- The offline wiki mirrors are CC BY-SA text by others: they stay in gitignored `.cache/`;
  cite a page's `url`, never commit the page.
- About to add a binary blob -> stop, ask. A task that seems to need game data in the repo
  -> do not; surface the conflict. Gate for rules 1, 4, and 5: `no-game-content.sh`.

## Gotchas

- The repo sits on a case-insensitive APFS volume: a case-only rename needs `git mv`.
- Xcode 27 ships without the Metal Toolchain; `make bootstrap` downloads it once.
- In `src/Sources/`, `OpenSky/` is app-only, `OpenSkyCLI/` CLI-only, `Shaders/` both, and each
  other folder a package module (gate: `cli-boundary.sh`). A folder is named after its target;
  only `openskycli` and the bundle IDs are lowercase, because macOS keys grants to them.
- Build in a linked worktree, one per issue. Two sessions in one checkout share one build
  tree, and two builds into one tree collide in xcodebuild's build database.
- Every build goes through `make`, in a background shell, so it uses the shared build tree and
  cache (`docs/tools/build-system.md`). `#filePath` reads `/^src/...`; find the checkout at runtime.
- Facts that expire (CI status, permissions, blocked hosts) live in `docs/tools/environment.md`
  with their date. Check it before fighting an odd failure.

## Environment & tech stack

- Metal 4 only. No OpenGL, no MoltenVK, no abstraction layer over another API.
- macOS 26+, Xcode 27, Apple Silicon only. Swift 6 mode, the same Swift locally and in CI
  (gate: `tools/lint/swift-baseline.sh`). C interop only behind a Swift interface.
- The game data root is a setting, never a constant; missing -> fail loud. The default probe
  is `~/Library/Application Support/Steam/steamapps/common/Skyrim Special Edition/`, and on
  this machine `/Volumes/data/steam/steamapps/`.
- Dependencies: the standard library and Apple frameworks first, then SwiftPM packages. Record
  each new one and its reason in `docs/decisions/`; its license must allow redistribution.

## Where things live

- `src/` holds the package, project, and `src/config/` (build settings, test plans). Anything
  that grows stays outside it: Xcode reads every file under `src/` at each build start.
- `docs/tools/modules.md` gives each module's layer and the import rules; read it before adding
  either. `reference/` holds the developer-only reference-game tooling.
- Run output goes to `.logs/<script>/<UTC timestamp>/`; link the run directory, never a loose
  file. Skills live in `.agents/skills/` (gate: `tools/lint/agent-files.sh`).

## Architecture

`docs/engine/architecture.md` explains the six styles, each with an example. When you add code:

- A feature uses another only through its `Interface` module (gate: `module-graph.sh`).
- Parsers and game rules are pure, values in and values out, inside a thin shell for files,
  clocks, Metal, audio, and UI (gates: `deterministic-rules.sh`, SwiftLint).
- Reach the outside world through a protocol (a port), so a test can pass a fake.
- Game logic goes in a coordinator in its feature module, not in `GameViewController` (SwiftLint).
- Change a data layout for speed only after a measurement shows the cost.
- Simulation runs on the main actor, in a fixed order, without `await`; file work runs off it
  (`docs/decisions/concurrency.md`; SwiftLint).

## Build, run, test

`make help` lists every target. `make fix` before committing; `make check` is the same gate without
writes, and CI runs it. `make install` refreshes `/Applications/OpenSky.app` after rendering work,
because the user checks progress there. A run costs minutes: make every edit, run one check, and fix
everything it reports at once. CI runs the whole unit plan on every push to a pull request; locally,
run the smallest plan that covers the change (`testing-and-verifying` skill) and record it in the
commit's `Tests:` section. A green build does not prove a triangle appeared. Unit-test every parser
and math routine with synthetic fixtures built in code.

## Open work, docs, and checking a behaviour

- Open work lives in GitHub issues and milestones (`starting-roadmap-work` skill).
- `docs/` holds only what the code cannot show (`writing-wiki-docs` skill).
- A new subsystem or visible behaviour gets an `openskycli game` command that sets it and a
  `state` read that shows it, in the same milestone (`driving-the-running-game` skill).

## Code quality

If a machine can check a rule, a machine checks it: a new check is a script in `tools/lint/`
with a self-check, and `make check` and CI run it with no other edit. Fix a finding; never
disable a rule. Size code to the limits in `tools/lint/.swiftlint.yml` while writing, not after
a failed `make fix`. Split a file at the 600-line warning, to below 600; `file-length.sh` fails
one over 800. `docs/tools/agent-instructions.md` lists every gate and what it checks.

## Writing style (agent output, docs, comments, commit bodies)

Write for young, capable students who learn English as a second language: short sentences
with one idea each, common words, and a technical term explained when it first appears. No
aphorisms, idioms, clever phrases, filler, hedging, or emojis. Prefer an example. Quote code
symbols and error strings verbatim. Use `[ERROR]`, `[WARNING]`, and `[INFO]` tags, unnumbered
headings, and British spelling ("colour"); names from Apple, Havok, and the game keep theirs.

Code documents itself through names and types. A comment holds only the why the code cannot
show: at most about 3 lines on a declaration, no history ("was", issue numbers), and no
restating of names. A format fact gets one line and a link to its `docs/formats/` page.

## How agents work here

- Confirm Skyrim internals against an open spec or observed data; training data is
  confidently wrong about byte layouts.
- A gap in the area you work on (a shader term, a record field): check the area for more, and
  build them all in the same PR, listed in its body. Its neighbours were usually never built.
- Each of these becomes its own GitHub issue, never an inline fix, and an issue body states
  intent with no file paths or code (`starting-roadmap-work` skill):
  - a performance idea, labelled `performance`, the title stating the win;
  - a pre-existing bug in an area the task does not touch, labelled `bug`, with how to
    reproduce it; fix it inline only when it blocks the task, and say so in the commit;
  - a difference from Skyrim, labelled `gap`; search the open ones first and add to a match.
- A value chosen without a source gets a row in `docs/engine/unverified-values.md`.
- Do the whole task in the main session; parallel agents have collided in one worktree. The
  one exception is the read-only clean-room read in `using-outside-sources`.

## Skills — load before the matching work

| Skill | Load it when |
| --- | --- |
| `starting-roadmap-work` | Choosing the next item, starting an issue, or closing a milestone |
| `committing-and-landing-work` | Committing, pushing, or opening and merging a pull request |
| `implementing-format-parsers` | Adding or changing any file format parser |
| `writing-wiki-docs` | Adding or materially changing anything under `docs/` |
| `probing-real-game-data` | Running engine code against the real Skyrim SE install |
| `developing-cli-commands` | Adding or changing an `openskycli` command, option, or help text |
| `driving-the-running-game` | Driving the live app with `openskycli game`, or the reference game with `openskycli reference` |
| `testing-and-verifying` | Running any test, build check, or verification, and before pushing |
| `consulting-uesp-wikis` | Looking up the Creation Kit or UESP wiki, or syncing their offline copies |
| `using-outside-sources` | Reading or taking anything from SKSE, CommonLibSSE, xEdit, nif.xml, OpenMW, or another third-party source |
| `writing-agent-instructions` | Adding, editing, or reviewing an `AGENTS.md`, skill, or memory, or learning a new rule |

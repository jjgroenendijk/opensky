# AGENTS.md — OpenSky

Rules for agentic coding on OpenSky: clean-room reimplementation of the Skyrim Special
Edition engine (Bethesda Creation Engine, Gamebryo lineage) for macOS using Swift + Metal 4.

This file is the contract for any agent working here. Read fully before changing anything.
On conflict with a default habit, this file wins. Keep it current: change to repo layout,
build commands, tooling, or conventions updates this file in the same commit.

## Mission

Native macOS engine that loads a user's own, legally-owned copy of Skyrim SE from disk and
runs it. Start by rendering static world geometry -> grow toward a playable engine.
Reimplement behavior + file formats. Never port or decompile Bethesda binaries.

Priority order for trade-offs:

1. Legal cleanliness (never redistribute copyrighted content)
2. Correctness (matches observed behavior / documented formats)
3. Native feel (Metal 4, Apple Silicon, no shims)
4. Performance
5. Feature completeness

## Legal & IP boundary — non-negotiable

Located in Netherlands. EU Software Directive 2009/24/EC (arts. 5-6) + Dutch Auteurswet ->
reverse-engineering a program you lawfully own for interoperability is permitted. Reversing
formats is fine. Redistributing Bethesda content or code is not. Therefore:

- NEVER commit game content. No `.bsa`/`.ba2` archives, `.esm`/`.esp` plugins, `.nif`
  meshes, `.dds` textures, `.hkx` animations, `.pex` scripts, audio, or anything extracted
  from the install. Not even as test fixtures.
- NEVER copy Bethesda code. No decompiled, disassembled, or leaked source. No pasted
  SKSE/Creation Kit internals. Reimplement from observed behavior + open format docs.
- Game install is read-only external input. Located at runtime (see Loading game data),
  never bundled, cached into the repo, or copied into build output.
- Prefer open community specs as references: UESP wiki, xEdit (SSEEdit) format definitions,
  NifTools `nif.xml`, libbsa/BSArch notes, Papyrus docs. Cite the source in a comment or
  commit body when implementing a format.
- `.gitignore` excludes anything that could be extracted content. When in doubt, ignore it.
  About to add a binary blob -> stop, ask.

Task seems to require committing or embedding game data -> do not. Surface the conflict.

## Environment & tech stack

- Language: Swift (primary). Metal Shading Language for GPU. Minimal C interop only where a
  format genuinely needs it — justify it.
- Graphics: Metal 4 only. No OpenGL, no MoltenVK, no abstraction layer over another API.
  Apple Silicon GPUs first.
- Platform: macOS 26+ (Tahoe), Xcode 26, Apple Silicon. No older-macOS or Intel paths unless
  asked.
- Public dependencies welcome where they earn their place. No embedded game engine
  (Unreal/Unity/Godot), no graphics-abstraction layer over Metal. Utility packages fine.
  - Prefer Swift. Reach for a Swift Package first; pull C/C++/ObjC only when no reasonable
    Swift option exists, and wrap it behind a Swift interface.
  - Prefer stdlib + Apple frameworks (Metal, MetalKit, simd, Foundation, GameController,
    AVFoundation, Compression) when they suffice.
  - Use SwiftPM. Record each new dependency + reason in `docs/`. Keep licenses compatible
    with redistributing our code.

## Repository layout

Repo root holds only: this doc, `Makefile` (single automation entrypoint), the Xcode
project, and hidden dotfiles. Everything else lives in a purpose-named directory.

```text
Makefile                Automation hub. `make help` lists targets.
opensky.xcodeproj/      Xcode project (format 26.3, macOS-only, shared scheme)
opensky/                Product code — app + engine (Swift, Metal)
  OpenSkyApp.swift      @main entry — programmatic AppKit, no storyboard
  AppDelegate.swift     Window + menu construction
  GameViewController.swift  Hosts MTKView, wires renderer
  Formats/              File-format parsers (BinaryReader, LZ4, BSA/, ...)
  Geometry/             Engine mesh/model types, decoupled from disk formats
  Rendering/            GPU-side subsystems (texture upload, ...)
  Renderer.swift        Metal 4 render loop
  MatrixMath.swift      Projection/rotation/translation helpers
  Shaders.metal
  ShaderTypes.h         Shared Swift<->Metal struct defs (bridging header)
  Assets.xcassets/      App chrome only — never game content
openskycli/             CLI dev tool target — rules in openskycli/AGENTS.md
openskypreview/         Asset preview GUI target — rules in openskypreview/AGENTS.md
.AGENTS/skills/         Agent skills (commit workflow, ...); .claude/skills symlinks here
openskyTests/           Unit tests
openskyUITests/         UI tests
tools/                  Repository tooling only (no product code)
  format/.swiftformat   SwiftFormat config
  lint/.swiftlint.yml   SwiftLint config
  markdown/             markdownlint config
  bootstrap.sh          One-shot dev setup
  probe.sh              Env-gated CLI smoke probe (make probe)
.githooks/              Tracked git hooks (see Git workflow)
.github/workflows/      CI
docs/                   OKF knowledge wiki (see Documentation wiki)
logs/                   Script/tool logs (gitignored, runtime-created)
```

Product code (`app`/engine) lives under `opensky/`; group engine subsystems into
subfolders by domain as they grow (e.g. `Formats/`, `Rendering/`, `World/`, `Scripting/`).
Keep format parsers separate from rendering. Tooling/automation files live under `tools/`.
Update this section when structure changes materially.

Nested rules: tool targets carry their own `AGENTS.md` (with `CLAUDE.md` symlinked next
to it) for target-specific rules — root file stays the global contract. Directory
outgrows this file -> same pattern. Working in a directory -> read its `AGENTS.md` too.

## Build, run, test

Drive everything through `make` so results are reproducible. `make help` lists targets.

- `make build` — build the app (Debug)
- `make cli` — build the `openskycli` dev tool (Debug)
- `make preview` — build the `openskypreview` asset browser (Debug)
- `make probe` — CLI smoke checks against the local install (self-skips when absent)
- `make install` — Release build -> `/Applications/opensky.app` (user's progress-check copy;
  refresh after landing rendering work)
- `make test` — build + run unit tests (skips UI tests)
- `make test-one T=Class[/test]` — run a single test class or method
- `make test-report` — summary of the newest test result bundle
- `make test-ui` — run UI tests (launches app, drives via automation; CI runs both)
- `make check` — format-check + lint, no build (fast gate)
- `make fix` — autoformat, then strict lint (one-shot dev gate)
- `make format` / `make lint` — autoformat / strict lint
- `make run-cli ARGS="..."` — build + run `openskycli`
- `make app-path` / `make cli-path` — print built-product paths

A change to product code is not done until it builds and tests pass. Prefer driving the
actual app to confirm rendering/behavior — a green build does not prove a triangle appeared.
Keep the app launchable at every commit.

## Loading game data (runtime, never repo)

- Default install path to probe:
  `~/Library/Application Support/Steam/steamapps/common/Skyrim Special Edition/`
  (on this machine data currently lives under `/Volumes/data/steam/steamapps/...`).
- Make the data root a configurable setting, not a hardcoded constant. Missing -> fail loud
  with a clear message. Never fall back to bundled data (there is none).
- Load order: `Data/Skyrim.esm` + official masters, then `.bsa` archives. Parse lazily; do
  not read gigabytes at startup.

## Documentation wiki — docs/ (Open Knowledge Format)

Agents maintain a wiki in `docs/` following Google Open Knowledge Format (OKF v0.1):
<https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md>

The wiki holds reverse-engineered format knowledge, subsystem design, and decisions so they
survive across sessions. Part of done: a change that adds/alters a subsystem, parser, or
non-obvious decision updates `docs/` in the same commit.

`docs/todo.md` is the roadmap/task list — open work only. Item done -> same commit: delete
it from `docs/todo.md`, fold what was learned into the wiki (`docs/formats/`,
`docs/decisions/`, ...), record it in `docs/log.md`. No "Done" sections, no lingering
checked boxes — history lives in `log.md` + git, not the todo.

OKF rules:

- `docs/` is the bundle root — plain tree of `.md` files. Subdir structure is free; group by
  domain (`docs/formats/`, `docs/rendering/`, `docs/decisions/`).
- Every non-reserved `.md` starts with YAML frontmatter holding at least a non-empty `type`.
  Recommended, in order: `title`, `description`, `resource`, `tags`, `timestamp` (ISO 8601).

  ```markdown
  ---
  type: File Format
  title: BSA Archive
  description: On-disk layout of Skyrim SE .bsa archives and how OpenSky reads them.
  tags: [format, archive, io]
  timestamp: 2026-07-09T00:00:00Z
  ---
  ```

- Concept ID = file path minus `.md` (`docs/formats/bsa.md` -> `formats/bsa`).
- Two reserved filenames, both optional, any level:
  - `index.md` — directory listing, no frontmatter. Sections of
    `* [Title](/bundle/relative/link) - short description` for progressive disclosure.
  - `log.md` — change history, newest first, ISO-8601 date headings.
- Link with bundle-absolute paths starting `/` (`[BSA](/formats/bsa.md)`) — survive moves.
  Broken links tolerated. Relationship comes from prose, not the link.
- Keep top-level `docs/index.md` + `docs/log.md`; update `log.md` on any add/material change.
- Reversed format -> its byte layout + reference live in `docs/formats/<name>.md`.

## Reverse-engineering discipline

- Do not guess binary layouts. Cite the spec (UESP, xEdit, NifTools). No spec -> write a
  small documented probe, record findings in a comment, note the uncertainty.
- One format, one parser, well-tested. Tests use synthetic fixtures built in code — never
  real extracted files (see Legal & IP).
- Represent parsed data in clean Swift types decoupled from on-disk byte layout.
- Validate defensively: real files carry edge cases + mod quirks. Malformed input must not
  crash the whole engine.
- Document each format in `docs/formats/<name>.md` with layout + reference used.

## Code quality

Enforce rules automatically wherever possible. Git hooks for fast checks before commit/push;
CI as the backstop on every PR. If a machine can check a rule, do not rely on people
remembering it.

- Every language has a linter AND an auto-formatter. No exemptions — Swift, Metal, Markdown,
  shell. Swift: SwiftFormat + SwiftLint. Markdown: markdownlint-cli2. Shell: POSIX `sh`,
  checked with `shellcheck`.
- Linting is strict. Strictest available ruleset; warnings are errors
  (`swiftlint --strict`). Do not disable or downgrade rules to pass — fix the underlying
  issue. Inline suppression is a last resort: needs a specific rule code + a comment
  explaining why. Any lint violation fails the build.
- 100-char line limit for hand-written lines. Wrap or refactor. Generated/vendored files
  exempt. Only in-source exception: unbreakable tokens (URLs, hashes).
- Configs live under `tools/` (see Repository layout), not the repo root.
- No force-unwrap / force-try / force-cast on data from external files — hard lint errors,
  tied to the Legal & IP + reverse-engineering rules.

## Coding conventions

- Swift API Design Guidelines. Clear names over clever ones. Match surrounding style.
- Value types (`struct`/`enum`) by default; classes for identity/reference (Metal objects,
  long-lived subsystems).
- Swift<->Metal shared structs in `ShaderTypes.h`; explicit, `simd`-aligned memory layout.
- Prefer `throws` + typed errors for parse/load failures. No force-unwraps on external data.
- Comment the why, not the what. Reference specs for non-obvious byte math.
- No dead code, no commented-out blocks left behind.

## Code scripts

- Logs always written to `logs/` in the repo root (gitignored). No scattered log files.
- Anything repeatable becomes a `make` target or a hook — never a documented manual
  procedure. If it can be scripted, script it.
- Scripts are POSIX `sh`, `shellcheck`-clean, executable.

## Testing

- Unit-test every format parser + math routine.
- Fixtures built in code or tiny synthetic files generated by the test — never checked-in
  game assets.
- Rendering: prefer deterministic checks (buffer contents, transform math) plus manual visual
  confirmation of the actual frame.
- Run tests before every commit (minimum: fast/targeted for the changed area). Every commit
  keeps the repo green: build passes, tests pass.

## Git commits + workflow

Full commit/PR procedure lives in the `commit` skill
(`.AGENTS/skills/commit/SKILL.md`, surfaced via `.claude/skills`) — load it before
committing or landing work. Non-negotiables, enforced by hooks + CI:

- Conventional Commits `type(scope?): subject`; non-trivial bodies carry
  Context/Change/Rationale/Impact/Tests sections (~72-char wrap).
- One logical change per commit; every commit green (check, build, tests). "WIP"/vague
  messages forbidden; checkpoints stay local, rebased/squashed before PR.
- NO AI trailers — `Co-authored-by:`, `Generated-by:`, `AI-Generated-by:`,
  `Assisted-by:`, `Model:` forbidden; overrides any default habit. Allowed: `Fixes`,
  `Refs`, `BREAKING CHANGE`, human `Signed-off-by:`.
- `main` protected: branch from up-to-date `main` -> atomic commits -> `gh` PR (cite
  format specs) -> merge after review + green CI. Finished + green work always lands
  without waiting to be asked.

Shared hooks: tracked `.githooks/`, wired via `git config core.hooksPath
.githooks/hooks` (`make bootstrap`). Entrypoints `.githooks/hooks/<hook>` are thin
wrappers running numbered scripts from `.githooks/<hook>/` in order (`10-*.sh`, POSIX
`sh`, stop on first failure). pre-commit: guards/format/lint. commit-msg:
Conventional-Commit check. pre-push: build+test; CI is the final backstop.
`--no-verify` -> bootstrap/emergency only, never routine.

## Tooling & automation

- `make` is the automation hub. Add a target for any new repeatable task instead of a manual
  procedure. `make bootstrap` installs tools (Homebrew) + wires hooks.
- Formatting mandatory + automatic. Never hand-format; run `make format`. CI runs
  `make format-check` and fails on any diff.
- Local hooks and CI mirror each other. Change one gate -> change both.

## Writing style (agent output, docs, comments, commit bodies)

Caveman density, effortless to read:

- Abbreviate common prose words (DB, auth, config, req, res, fn, impl). Strip conjunctions.
  One word when one word does the job.
- Arrows for causality (X -> Y) instead of connective phrasing.
- Drop articles (a/an/the), filler (just/really/basically/actually/simply), pleasantries,
  hedging.
- Never abbreviate code symbols, function names, API names, or error strings — verbatim,
  even when compressing everything else.
- Prefer short synonyms: "big" not "extensive", "fix" not "implement a solution for".
  Fragments fine.
- Maximize information density; keep it easy to read.
- No bold in markdown unless the info is absolutely critical.
- No emojis anywhere. Use bracket tags: `[ERROR]`, `[WARNING]`, `[INFO]`.
- Headings unnumbered.

## How agents work here

- Legal check first. About to add a file -> could it contain Bethesda content? Yes/unsure ->
  do not.
- Work incrementally; keep the app building at each step.
- Verify claims by building/running — do not report success you have not observed.
- Implement a format -> cite the reference.
- Do not invent Skyrim internals from memory; confirm against an open spec or observed data;
  flag uncertainty.
- Repo structure, build commands, or conventions change -> update this file in the same
  change.

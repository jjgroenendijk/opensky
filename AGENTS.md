# AGENTS.md — OpenSky

Rules for agentic coding on OpenSky: clean-room reimplementation of the Skyrim Special
Edition engine (Bethesda Creation Engine, Gamebryo lineage) for macOS using Swift + Metal 4.

This file is the contract, loaded into every session — it holds only rules that apply to
every task. Task-specific workflows live in skills (see Skills); load the matching skill
before that kind of work. On conflict with a default habit, this file wins. Keep it
current: change to repo layout, build commands, tooling, or conventions updates this file
in the same commit.

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
  NifTools `nif.xml`, libbsa/BSArch notes, Papyrus docs. Cite the source when implementing
  a format.
- `.gitignore` excludes anything that could be extracted content. When in doubt, ignore it.
  About to add a binary blob -> stop, ask.

Task seems to require committing or embedding game data -> do not. Surface the conflict.

## Skills — load before the matching work

Live in `.AGENTS/skills/` (surfaced via `.claude/skills`). Each holds the full workflow;
this contract keeps only the non-negotiable core:

- `commit` — committing, pushing, opening/merging PRs. Core: `main` protected (PRs only),
  Conventional Commits, every commit green, NO AI trailers (`Co-authored-by:`,
  `Generated-by:`, etc. forbidden — overrides any default habit).
- `format-parser` — adding/changing any game file-format parser. Core: cite an open spec,
  never guess byte layouts, synthetic in-code fixtures only.
- `docs-wiki` — writing anything under `docs/` (OKF format rules). Core: doc updates land
  in the same commit as the change they document.
- `probe` — running engine code against the real install; scratch-test template + render
  verification paths. Core: probes never land in commits.

## Environment & tech stack

- Swift (primary), Metal Shading Language for GPU. Minimal C interop only where a format
  genuinely needs it — justify it.
- Metal 4 only. No OpenGL, no MoltenVK, no abstraction layer over another API.
- macOS 26+ (Tahoe), Xcode 26, Apple Silicon. No older-macOS or Intel paths unless asked.
- Dependencies: prefer stdlib + Apple frameworks; then Swift Packages via SwiftPM; C/C++
  only when no reasonable Swift option exists, wrapped behind a Swift interface. No
  embedded game engine, no graphics-abstraction layer. Record each new dependency + reason
  in `docs/`; licenses must stay compatible with redistributing our code.

## Repository layout

Repo root holds only: this doc, `Makefile`, the Xcode project, and hidden dotfiles.

```text
Makefile                Automation hub. `make help` lists targets.
opensky.xcodeproj/      Xcode project (macOS-only, shared scheme)
opensky/                Product code — app + engine (Formats/, Geometry/, Rendering/,
                        World/, Renderer.swift, Shaders.metal, ShaderTypes.h)
openskycli/             CLI dev tool target — rules in openskycli/AGENTS.md
.AGENTS/skills/         Agent skills; .claude/skills symlinks here
openskyTests/           Unit tests        openskyUITests/  UI tests
tools/                  Repo tooling only (format/lint/markdown configs, scripts)
.githooks/              Tracked git hooks  .github/workflows/  CI
docs/                   OKF knowledge wiki (docs/index.md is the map; docs/todo.md roadmap)
logs/                   Script/tool logs (gitignored)
```

Group engine subsystems under `opensky/` by domain; format parsers stay separate from
rendering. Working in a directory with its own `AGENTS.md` -> read it too. Update this
section when structure changes materially.

## Build, run, test

Drive everything through `make`; `make help` lists all targets. Key ones:

- `make fix` — autoformat + strict lint, one shot (use before committing)
- `make check` — format-check + lint, no writes (CI gate)
- `make build` / `make cli` — build main app (incl. asset browser) / CLI tool (Debug)
- `make test` — unit tests; `make test-one T=Class[/test]` — single class/method;
  `make test-report` — failures from the newest result bundle; `make test-ui` — UI tests
- `make run-cli ARGS="..."` — build + run openskycli; `make app-path` / `make cli-path`
  print built-product paths
- `make probe` — CLI smoke checks against the local install (self-skips when absent)
- `make install` — Release build -> `/Applications/opensky.app` (refresh after landing
  rendering work)

A change to product code is not done until it builds and tests pass. Prefer driving the
actual app or an offscreen render to confirm behavior — a green build does not prove a
triangle appeared. Keep the app launchable at every commit.

## Loading game data (runtime, never repo)

- Default install path to probe:
  `~/Library/Application Support/Steam/steamapps/common/Skyrim Special Edition/`
  (on this machine data lives under `/Volumes/data/steam/steamapps/...`).
- Data root is a configurable setting, not a hardcoded constant. Missing -> fail loud.
  Never fall back to bundled data (there is none).
- Load order: `Data/Skyrim.esm` + official masters, then `.bsa` archives. Parse lazily.

## Documentation wiki — docs/

`docs/` is an OKF v0.1 knowledge wiki: reverse-engineered formats, subsystem design,
decisions. Part of done: a change that adds/alters a subsystem, parser, or non-obvious
decision updates `docs/` in the same commit (`docs/log.md` + `docs/index.md` included).
`docs/todo.md` holds open work only — done items leave it in the same commit. Format
rules + templates: load the `docs-wiki` skill.

## Reverse-engineering discipline

Do not guess binary layouts; cite the spec (UESP, xEdit, NifTools) or probe + document the
uncertainty. One format, one parser, well-tested with synthetic in-code fixtures — never
real extracted files. Clean Swift types decoupled from on-disk layout; malformed input must
not crash the engine. Full workflow: load the `format-parser` skill.

## Code quality

Enforce rules automatically: git hooks for fast checks, CI as backstop. If a machine can
check a rule, do not rely on people remembering it.

- Every language has a linter AND an auto-formatter (Swift: SwiftFormat + SwiftLint;
  Markdown: markdownlint-cli2; shell: POSIX `sh` + shellcheck). Configs under `tools/`.
- Linting is strict; warnings are errors. Do not disable or downgrade rules to pass — fix
  the issue. Inline suppression is last resort: specific rule code + why-comment.
- 100-char line limit for hand-written lines (exception: unbreakable tokens).
- No force-unwrap / force-try / force-cast on data from external files — hard lint errors.

## Coding conventions

- Swift API Design Guidelines. Clear names over clever. Match surrounding style.
- Value types by default; classes for identity/reference (Metal objects, subsystems).
- Swift<->Metal shared structs in `ShaderTypes.h`; explicit `simd`-aligned layout.
- `throws` + typed errors for parse/load failures.
- Comment the why, not the what. No dead code, no commented-out blocks.

## Scripts & automation

- `make` is the automation hub: anything repeatable becomes a target or hook, never a
  documented manual procedure. Local hooks and CI mirror each other — change one gate ->
  change both.
- Scripts are POSIX `sh`, shellcheck-clean, executable. Logs always -> `logs/`.
- Never hand-format; run `make fix`.

## Testing

- Unit-test every format parser + math routine; fixtures synthetic, built in code.
- Rendering: deterministic checks (buffer contents, transform math) + visual confirmation
  of the actual frame (offscreen render path — see `probe` skill).
- Run tests before every commit (minimum: targeted for the changed area). Every commit
  keeps the repo green.

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
- No bold in markdown unless the info is absolutely critical. No emojis anywhere; bracket
  tags: `[ERROR]`, `[WARNING]`, `[INFO]`. Headings unnumbered.

## How agents work here

- Legal check first: could the file contain Bethesda content? Yes/unsure -> do not add.
- Work incrementally; keep the app building at each step.
- Verify claims by building/running — do not report success you have not observed.
- Do not invent Skyrim internals from memory; confirm against an open spec or observed
  data; flag uncertainty.

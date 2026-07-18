# AGENTS.md — openskypreview

Asset preview GUI target. Root `/AGENTS.md` is the contract; this file adds
preview-specific rules. Full tool reference: `docs/tools/preview-gui.md`.

## What it is

AppKit browser over VFS archive entries + Skyrim.esm records with offscreen-rendered
NIF/DDS previews. M2 scope: browse + single-asset preview. Grows into the world
viewer/test harness later.

## Build + verify

- `make preview` — build (Debug).
- Do not launch the app just to verify — app launches appear on the user's screen.
  Verification path: unit tests over `opensky/Preview/` + env-gated
  `PreviewRealDataTests` (offscreen renders -> `logs/preview-*.png`; pass data root as
  `TEST_RUNNER_OPENSKY_DATA_ROOT` in the xcodebuild environment).

## Rules

- Browse/preview logic stays AppKit-free under `opensky/Preview/`, unit-tested without
  a window. App side (`openskypreview/`) only wires UI.
- Previews render through the engine's own path (`Renderer.renderOffscreen`,
  `MeshLibrary`, `TextureLoader`) — never a second asset pipeline. Preview shows what
  the engine samples.
- Failures degrade to `[ERROR]`/`[WARNING]` text in the pane — never crash on
  malformed data (mod-quirk rule). Missing install -> in-window message.
- Long work off the main thread (catalog load, record filter); stale async results
  dropped via generation counter — preserve the pattern.
- UI/scope change -> same commit updates `docs/tools/preview-gui.md`.

# Change log

Newest first. ISO-8601 date headings. See AGENTS.md "Documentation wiki".

## 2026-07-09

* **Localized string tables**: `Formats/Strings/StringTable.swift` —
  `.strings`/`.dlstrings`/`.ilstrings` reader (header + directory, zstring
  vs length-prefixed framing, lenient UTF-8 -> windows-1252 decode).
  `BinaryReader.readZStringData` added for caller-chosen encodings. Doc:
  [string tables](/formats/strings.md). Verified against all 273 vanilla
  table files (10 languages, 834 865 strings, 0 failures).
* **FormID + master resolution**: `Formats/ESM/PluginHeader.swift` (TES4
  HEDR/CNAM/SNAM/MAST decode) + `FormID.swift` (`FormID`, `ResolvedFormID`,
  `FormIDResolver` — top byte -> master index, out-of-range clamped to the
  plugin, null -> nil). Doc: [FormID](/formats/formid.md). Verified against
  all five vanilla masters. Lint config: `inclusive_language` now allows
  "master" — TES4 domain term (MAST), spec traceability.
* **ESM/ESP container walk**: `Formats/ESM/` — TES4 + top-group index over a
  memory-mapped plugin, lazy GRUP/record traversal, zlib record decompression
  (`Formats/Zlib.swift` over Apple Compression), field iterator with XXXX size
  extension, shared `FourCC` type code. Doc: [ESM container](/formats/esm.md).
  Verified against vanilla Skyrim.esm (870 k records, all payloads parse).
* **VFS / resource manager**: `GameData/VirtualFileSystem.swift` +
  `ArchiveLoadOrder.swift` — one lookup layer over the data root. Loose files
  override archives, later archives override earlier, case/separator-
  insensitive keys, lazy archive open, malformed archives logged + skipped.
  Load order: ini resource lists (Skyrim.ini -> Skyrim_Default.ini -> built-in
  vanilla) then plugin-named archives. Doc: [VFS](/formats/vfs.md).
* **Game data locator**: `GameData/GameDataLocator.swift` — env var ->
  UserDefaults -> default Steam path, fail-loud alert + os_log on missing/invalid,
  no silent fallback. Doc: [game data locator](/engine/game-data-locator.md).
  Verified against real install (`/Volumes/data/steam/...`) via unified log.
* **Roadmap**: expanded [todo](/todo.md) into full milestone plan (M1 game data ->
  M4 playable) + agent handoff instructions (branch/PR state, machine quirks,
  format-work discipline).
* **BSA parser**: BSA v105 reader (`Formats/BSA/`), clean-room LZ4
  frame/block decoder, bounds-checked BinaryReader. Docs:
  [BSA format](/formats/bsa.md). Verified against vanilla SSE archives at
  runtime; synthetic-fixture unit tests.
* **macOS conversion**: iOS template -> native macOS-only app, Xcode 26.3 project
  format (objectVersion 100), programmatic AppKit + Metal 4 rotating-triangle
  skeleton, shared scheme, MatrixMath + tests. See
  [decision](/decisions/native-macos-app.md). Rewrote [todo](/todo.md) as roadmap.
* **Creation**: Initialized docs wiki and project development tooling
  (AGENTS.md, git hooks, lint/format, CI).

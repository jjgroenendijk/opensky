---
name: using-outside-sources
description: Decides which third-party sources about Skyrim internals OpenSky may use and how -
  SKSE (scripts, C++ source, co-save), CommonLibSSE, the Address Library, xEdit, nif.xml,
  hkxcmd, OpenMW, Havok reimplementations, mod source code - with a tier for each source, what
  may be taken from it, and the clean-room read for source code built on the game binary. Use
  before reading, citing, or taking anything from such a source, when a task asks how SKSE or
  CommonLibSSE does something, or when deciding whether a source is allowed.
---

# Using outside sources

Copyright protects code and its structure, not facts or behaviour. So OpenSky may learn what
the game does from any source, but must never take code or structure that came from the game
binary. `docs/decisions/clean-room-sources.md` gives the legal reasons.

Two terms:

- An **interop fact** is a value or behaviour visible outside the binary: bytes in a data file,
  a value a script or condition function returns, or what a player can see happen. Example:
  `GetAttackState` returns 2 while the weapon swings.
- **Binary structure** exists only inside `SkyrimSE.exe`: class and field layouts, offsets,
  vtable slots, function addresses, and class names from the binary's RTTI (runtime type
  information), such as `TESObjectREFR`.

A name that appears in a game data file is an interop fact. Havok class names in an HKX file,
record signatures, and Papyrus function names are fine to use.

## Tiers

| Tier | What you may take | Process |
| --- | --- | --- |
| 1 | Interop facts | Cite the source, confirm on the install |
| 2 | Interop facts only, never code logic or names | Clean-room read (below) |
| 3 | Nothing | Do not open it |

| Source | Tier | Notes |
| --- | --- | --- |
| UESP and Creation Kit wikis | 1 | `consulting-uesp-wikis` skill |
| xEdit `wbDefinitionsTES5.pas`, NifTools `nif.xml`, BSArch notes | 1 | Format specs |
| HKX2Library, DSMapStudio HKX2, hkxparse (MIT) | 1 | `docs/decisions/havok-behavior-scope.md` |
| OpenMW | 1 | Morrowind engine; its rules may differ from Skyrim |
| SKSE docs and `.psc` script files | 1 | The script interface we must match |
| SKSE co-save (`.skse`) format | 1 | SKSE's own format, read so existing saves load |
| SKSE C++ source (`src/skse64`) | 2 | Source available, not open source |
| CommonLibSSE | 2 | MIT licence, but built from the binary |
| hkxcmd `compat/` | 2 | Built against the Havok SDK |
| Address Library, offset or RTTI dumps | 3 | Only binary structure |
| Bethesda code, decompiles, leaks, Havok SDK headers | 3 | Root `AGENTS.md`, legal section |
| Skyrim Together source | 3 | Hooks the binary; SKSE's licence accuses it of copyright infringement |

A source not in the table: ask whether its authors wrote it from data files and play
(Tier 1), from the binary (Tier 2), or whether it is the binary's structure itself (Tier 3).
Unsure -> treat it as the higher tier, ask the user, then add the source to the table.

## Tier 1

1. Note the exact page, version, or commit you read.
2. Confirm each fact on the install or in the running game (`probing-real-game-data`,
   `driving-the-running-game`). A source can be wrong.
3. Cite the source in the `docs/` page or the doc comment that holds the fact.

## Tier 2: the clean-room read

The session that writes OpenSky code never reads Tier 2 source. A read-only sub-agent reads
it and returns a prose description. Because the sub-agent edits nothing, it cannot collide
with the main session's worktree.

1. Look for a Tier 1 source first. Use Tier 2 only when no Tier 1 source covers the fact.
2. Start an `Explore` sub-agent. Its prompt names the function or value, and says that the
   reply must:
   - describe only interop facts: inputs, outputs, edge cases, error results, constants
     visible from scripts or data files;
   - contain no code, pseudocode, offsets, addresses, field names, or class names from the
     source;
   - name the file and commit it read.
3. Check the reply against the same list. A reply that breaks it is thrown away. Do not
   carry any part of it into the repo, and start a new sub-agent with a stricter prompt.
4. Write the description into the matching `docs/` page, citing the file and commit as
   "behaviour described from".
5. Implement from the description, in OpenSky's own names and structure.
6. Confirm the behaviour in the reference game with SKSE installed (`reference/`,
   `docs/tools/reference-game.md`), or record in the page that it is unconfirmed.

The main session may open the Tier 2 source's README, licence, and file list to find the
right file for the prompt. It does not open source files.

## Never

- Never paste, translate, or paraphrase line by line any code from a Tier 2 or Tier 3 source.
- Never name an OpenSky type, case, or field after binary structure, such as an RTTI class name
  or a CommonLibSSE enum name. Use OpenSky's own name.
- Never write an offset or address from Tier 2 or Tier 3 into the repo. OpenSky does not share
  the game's memory layout, so these have no use anyway.
- A task that needs binary structure, such as loading SKSE DLL plugins, is out of scope.
  Surface it to the user.

---
type: Decision
title: ActionScript 2 runtime scope for vanilla menus
description: Build a full AS2 interpreter for the 56 opcodes the vanilla Interface movies use, and
  phase the open-ended host API behind a logged no-op plus tally.
tags: [decision, swf, as2, ui, scaleform]
---

# ActionScript 2 runtime scope

OpenSky renders the player's own vanilla `Interface/*.swf` movies instead of a native UI. The
objection to that route was that reimplementing ActionScript is a second virtual machine of unbounded
size, next to the Papyrus VM. This page answers that objection with a measurement. The numbers are on
the [AS2 census](/decisions/swf-as2-census.md) page.

## Context

The movies decode and render ([SWF container](/formats/swf.md), [SWF layer](/rendering/swf-layer.md)).
But many draws resolve to alpha 0 through their `CXFORM`, and some movies change no pixels at all on
frame 1. Those menus are blank because their ActionScript has not run, not because decoding failed.

## Decision

Build the AS2 interpreter, scoped and phased as follows.

The virtual machine covers the full measured opcode set, because that set is closed and small: 56
opcodes over 533,562 records, with no unknown opcode. Splitting a 56-entry table across phases would
cost more in debugging partial runs than implementing it all, and the opcodes that never appear
already remove the costly subsystems (`with`, exceptions, URL loading).

The host API is the open-ended part: 3,382 distinct names. That is what gets phased. One mechanism
makes phasing safe, and it is a requirement: **every unimplemented host API resolves to a logged no-op
plus a tally entry.** A movie that reaches a missing API degrades (a control is inert, a field stays
empty) and does not throw, and the tally is the ranked work list for the next phase. The same rule
covers any opcode a non-vanilla movie brings. So the project never has to implement all 3,382 names
to make progress, and never has to guess what comes next.

Execution is bounded by an action budget and depth limits, and bad bytecode never crashes the engine.
See [Budget and safety](#budget-and-safety).

## Phases

| Phase | Scope | Unlocks |
|---|---|---|
| Core VM | All 56 opcodes, scope and prototype chains, calls, language natives | Every class definition in the install loads |
| Display objects | `MovieClip`, `TextField`, `Stage`, `Selection`, properties, timeline control | A menu builds a live display list, including content frame 1 hides |
| Framework and bridge | CLIK and the `gfx` library, focus and navigation, input routing, `GameDelegate` | One vanilla menu opens, navigates, and closes under real input |
| Per-menu data APIs | Menu-specific host APIs backed by game data | Each menu's real content |

### Core VM

Besides the opcodes, the class code needs the language natives: `Object`, `Array`, `String`,
`Number`, `Boolean`, `Math`, `ASSetPropFlags`, and `Object.registerClass`. The prototype chain must
be real, because `ActionExtends`, `ActionInstanceOf`, and `ActionCastOp` depend on it. `addProperty`
(1,535 uses) means getter and setter properties are needed here, not later; the `__get__entryList`
and `__set__disabled` names are the compiler's evidence. The exit check is that every `DoInitAction`
block runs to the end with no unimplemented opcode and no budget abort. Host API misses are expected
at this stage.

### Display objects

`MovieClip`, `TextField`, `Stage`, and `Selection` sit over the existing display list and text
layout, with the properties the movies touch: `_x`, `_y`, `_width`, `_height`, `_visible`, `_alpha`,
`_name`, `_parent`, and the CLIK pairs `__width` and `__height`. Timeline control means `gotoAndStop`,
`gotoAndPlay`, `play`, and `stop`. `ActionGoToLabel` and the string form of `gotoAndStop` need the
`FrameLabel` tag (43), which vanilla uses. The exit check is a changed-pixel delta on movies that
change nothing statically.

### Framework and bridge

Enough of the `gfx` library for a real menu: `EventDispatcher`, `addEventListener`, `dispatchEvent`,
`Constraints`, the focus path (`FocusHandler`, `setFocus`, `_focused`, `focusIndicator`),
`NavigationCode`, and the button and list controls built on them (`setState`, `ButtonChange`,
`thumb`, `track`). Real keyboard and mouse input goes into that focus path, not into clip events.
`GameDelegate` works in both directions. The exit check is one vanilla menu opening, navigating, and
closing under real input, with UI-state and pixel evidence, and with `Developer > UI Lab` showing
movie state, the invoke log, and the tally.

### Per-menu data APIs

Deferred on purpose. `InventoryDefines`, `_CategoriesList`, `EntriesA`, and `iSelectedIndex` are data
contracts that mean nothing before the engine has the data to fill them. Each lands with the work
that owns its data: the [inventory menu](/engine/inventory-menu.md), the
[journal](/engine/journal.md), the [dialogue menu](/engine/dialogue-menu.md), and the
[system menu](/engine/system-menu.md), which fills `startmenu.swf`'s `EntriesA` through
`sendMenuProperties`. `modmanager.swf` has no owner yet. Until an owner lands, each API is a logged
no-op with a tally entry.

## Choosing targets

Small movies come first, because a failure in a 6-block movie can be diagnosed and one in a
250-block movie cannot:

- `book.swf`: 6 action blocks. It encodes draws but changes 0 pixels on frame 1 (the alpha-0
  `CXFORM` case), so pixels change only if the ActionScript ran.
- `loadingmenu.swf`: 10 draws and 37 glyphs, and 0 changed pixels statically. The same signal, with
  text.
- `bookmenu.swf`: 30 sprites and one filter. Small, but a real display list.

`hudmenu.swf` does not navigate, but it tests the engine-to-movie direction of the bridge alone.

Size rank is not target rank. `quest_journal.swf` (33,692 records), `modmanager.swf` (29,383), and
`inventorymenu.swf` (24,754) are the largest AS2 users, and each depends on a per-menu data contract,
so none is a good first target.

`startmenu.swf` was first picked as the interactive target on two assumptions that measurement
disproved. Its entries are not fixed in the movie: the engine pushes all of them through
`sendMenuProperties`. And it is the title screen, not the in-game system menu, so it has no Settings
row. `tweenmenu.swf` was the first interactive menu instead. The
[system menu](/engine/system-menu.md) page covers `startmenu.swf`.

## Budget and safety

The interpreter runs untrusted content. Vanilla movies come from the user's install, but mod movies
are a goal, and a script that loops forever must not take the engine with it.

- Bounded execution: an action budget and call and re-entry depth limits, shown in the UI Lab tally.
  Going past one aborts that block with a logged diagnostic, and the frame goes on. The largest
  vanilla block has 5,886 records, so a budget far above that still catches a runaway fast. The
  values are on the [AS2 runtime](/engine/as2-runtime.md) page.
- Bad bytecode never crashes. The parser turns a malformed action stream into a warning and stops that
  stream, like the display list parser does with a bad control tag. A type error, a missing member,
  or a jump to a bad offset is a logged diagnostic and a no-op.
- No outside reach. `ActionGetURL` and `ActionGetURL2` are not implemented and stay logged no-ops.
  The runtime has no file, network, or process access, and the host API is an explicit allowlist, not
  a bridge to any engine call.
- `ActionTrace` output goes to the engine log and UI Lab, never to the rendered frame.

## Residual risk

- The Adobe SWF specification stops at the bytecode. It does not define the player object model
  (`MovieClip`, `TextField`, `Selection`, `ASSetPropFlags`, prototype rules). Those come from public
  ActionScript 2 documentation and from observed bytecode, which is a weaker source.
- The Scaleform GFx extensions have no public specification. `gfx.io.GameDelegate` and CLIK are
  documented only as component usage. The mitigation is that the components ship inside the movies as
  AS2, so OpenSky reads what CLIK does from bytecode it already decodes.
- `ActionDefineFunction2` register rules are a trap. The preload and suppress flags decide which of
  `this`, `arguments`, `super`, `_root`, `_parent`, and `_global` take which register. One mistake
  shifts every register in the body, and nothing reports an error.
- A menu can run with no missing op and still be wrong. Pixel and UI-state evidence stays the check.

The `_global` scope and constant-pool lifetime questions are settled on the
[AS2 runtime](/engine/as2-runtime.md) page: one machine per movie, and a function keeps the pool it
was defined under.

## Legal position

The interpreter is reimplemented from the public Adobe SWF File Format Specification, version 19, from
public ActionScript 2 documentation for the object model, and from observation of the user's own
files. No Scaleform GFx SDK code is used, and no code from another Flash or SWF player is copied or
adapted. Unit tests build synthetic movies in code, never from an extracted `.swf`, and movies load
from the user's install at run time.

## References

- Adobe SWF File Format Specification, version 19: chapter 5 "Actions" (`DoAction` and
  `ACTIONRECORD` p. 63, `DoInitAction` p. 108, per-action tables pp. 64-116), and chapter 3 "The
  display list" (`CLIPACTIONS` pp. 36-37, `ClipEventFlags` pp. 48-49).
- [AS2 census](/decisions/swf-as2-census.md): the measurement.
- [SWF container](/formats/swf.md): tag coverage and the action tags.
- [CLI](/tools/cli.md): `openskycli swf action-sweep`.

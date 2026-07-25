---
type: Decision
title: ActionScript 2 runtime scope for vanilla menus
description: Build a bounded AS2 interpreter for the 56 opcodes vanilla Interface movies
  actually use, and phase the open-ended host API behind a logged no-op plus tally.
tags: [decision, swf, as2, ui, scaleform, milestone-8]
timestamp: 2026-07-25T00:00:00Z
---

# ActionScript 2 runtime scope

Closes milestone item 8.3.1. Binding for 8.3.2 (the interpreter), 8.3.3 (the interactive
acceptance), 8.4.2 (the HUD bridge), 8.5.1 (the system menu), and for every later milestone
that drives a vanilla menu (M12 inventory, M13 journal, M17 dialogue).

## Context

Milestone 8 changed direction on 2026-07-23 (issue #99): instead of a native UI, OpenSky
renders the player's own vanilla `Interface/*.swf` movies. The scrapped native-UI decision
recorded one specific objection to that route — that reimplementing ActionScript means
signing up for a "full second VM project" of unbounded size, next to the Papyrus VM that
M11 already owes. That objection was reasonable but untested, because nobody had measured
what the vanilla movies actually execute.

Milestone 8.2 established that the movies decode and render: 53 movies parse with zero
failures, 2,677 shapes tessellate, 97 fonts and 665 `DefineEditText` fields lay out, and
frame 1 composites over the 3D frame. Milestone 8.2.5 also established the shape of the
remaining gap. Of the 1,902 frame-1 draws across the install, 1,032 resolve to alpha 0
through their `CXFORM`, and 20 of the 53 movies change no pixels at all. Those menus are
blank because their ActionScript has not run, not because decoding failed. See
[SWF container](/formats/swf.md) and [screen-space UI layer](/rendering/ui.md).

Milestone 8.3.1 then made the bytecode reachable and measured it. Stage 1 (commit
`ea35008`) added the `ACTIONRECORD` framing layer — `SWFActionParser`, `SWFClipActions`,
`SWFTimeline` — so that `DoAction`, `DoInitAction`, and `CLIPACTIONS` blocks on the main
timeline and inside every sprite survive decoding, each record carrying its own byte offset
so an interpreter can seek to it. Stage 2 (commit `989a851`) added
`openskycli swf action-sweep` and `SWFActionInventory`, which tally the opcode frequency,
the structurally-resolved host API name surface, the clip-event usage, and the function and
constant-pool structure across the whole install. Nothing executes bytecode yet.

This document reports that measurement and answers the "second VM project" risk with it.

## Decision

Build the AS2 interpreter, scoped and phased as follows.

The virtual machine is implemented in full for the measured opcode set, because that set is
closed and small: 56 distinct opcodes over 533,562 records, with zero unknown opcodes. The
VM is not the open-ended part of this work and does not need phasing beyond a single
implementation pass.

The host API is the open-ended part — 3,382 distinct member and function names — and it is
what gets phased. The mechanism that makes phasing safe is fixed here as a requirement, not
an option: **every unimplemented host API resolves to a logged no-op plus a tally entry.**
A movie that reaches an API OpenSky does not implement degrades (a control renders inert, a
field stays empty) instead of throwing, and the tally is the prioritised work list for the
next phase. The same rule applies to any opcode a future non-vanilla movie introduces.

Work proceeds in four phases (see [Phased subset plan](#phased-subset-plan)). Phase 4 —
per-menu game-data APIs — is explicitly deferred to the milestones that own the data, as
the roadmap already anticipates for M12.5, M13.4, and M17.2. Milestone 8.3 is complete
when one menu is interactive on phases 1 through 3; it is not complete when every menu
works, and no schedule assumes otherwise.

Execution is bounded by a per-frame record budget and a recursion depth cap, and the
interpreter never crashes the engine on bad bytecode. See
[Budget and safety posture](#budget-and-safety-posture).

## Evidence: the measurement

All numbers below come from `openskycli swf action-sweep` run against the user's own
install, over all 53 vanilla `Interface/*.swf` movies. The full report is captured to
`logs/swf-action-sweep.log`, which is gitignored and never committed — it is derived from
game content. Reproduce it with `make run-cli ARGS="swf action-sweep"`.

Totals: 53 movies, 0 failed. 3,414 action blocks — 2,163 `DoAction`, 1,127 `DoInitAction`,
124 `CLIPACTIONS`. 533,562 `ACTIONRECORD`s. 56 distinct opcodes, 0 unknown opcodes (none
outside the Adobe action table), 0 undecoded opcodes (every record that appears has typed
operands, not retained raw bytes), and 0 parse warnings.

Structure: `ActionDefineFunction2` 10,575 records against `ActionDefineFunction` 1,323, so
vanilla is overwhelmingly register-based SWF 7 function bodies; the highest register count
used is 23. `ActionConstantPool` 936 records, largest pool 404 entries. `ActionWith` 0 and
`ActionTry` 0. The largest single action block is 32,240 bytes and 5,886 records.

## The opcode surface is closed and small

Fifty-six opcodes, zero unknown, over half a million records. This is the direct answer to
the "second VM project" risk on the bytecode side: the work is enumerable, and the table
below is the whole of it. There is no long tail waiting to be discovered in vanilla, and
`tools/probe.sh` now fails the probe if any unknown opcode ever appears, so the claim stays
enforced rather than remembered.

| Opcode | Name | Records | Movies |
|---|---|---|---|
| `0x96` | `ActionPush` | 191,644 | 44 |
| `0x4e` | `ActionGetMember` | 83,487 | 44 |
| `0x17` | `ActionPop` | 37,127 | 44 |
| `0x4f` | `ActionSetMember` | 30,757 | 43 |
| `0x12` | `ActionNot` | 28,569 | 41 |
| `0x52` | `ActionCallMethod` | 28,074 | 44 |
| `0x9d` | `ActionIf` | 24,873 | 41 |
| `0x1c` | `ActionGetVariable` | 21,062 | 44 |
| `0x87` | `ActionStoreRegister` | 13,807 | 42 |
| `0x49` | `ActionEquals2` | 12,474 | 41 |
| `0x8e` | `ActionDefineFunction2` | 10,575 | 43 |
| `0x99` | `ActionJump` | 7,760 | 41 |
| `0x3e` | `ActionReturn` | 7,280 | 41 |
| `0x4c` | `ActionPushDuplicate` | 4,615 | 41 |
| `0x47` | `ActionAdd2` | 4,401 | 42 |
| `0x0b` | `ActionSubtract` | 2,686 | 42 |
| `0x43` | `ActionInitObject` | 2,442 | 41 |
| `0x66` | `ActionStrictEquals` | 1,876 | 35 |
| `0x67` | `ActionGreater` | 1,666 | 41 |
| `0x48` | `ActionLess2` | 1,592 | 39 |
| `0x40` | `ActionNewObject` | 1,499 | 42 |
| `0x42` | `ActionInitArray` | 1,413 | 41 |
| `0x07` | `ActionStop` | 1,379 | 41 |
| `0x3d` | `ActionCallFunction` | 1,373 | 41 |
| `0x9b` | `ActionDefineFunction` | 1,323 | 41 |
| `0x50` | `ActionIncrement` | 1,297 | 41 |
| `0x1d` | `ActionSetVariable` | 1,019 | 34 |
| `0x88` | `ActionConstantPool` | 936 | 44 |
| `0x0c` | `ActionMultiply` | 718 | 41 |
| `0x60` | `ActionBitAnd` | 693 | 34 |
| `0x0d` | `ActionDivide` | 676 | 41 |
| `0x26` | `ActionTrace` | 522 | 38 |
| `0x3a` | `ActionDelete` | 506 | 41 |
| `0x54` | `ActionInstanceOf` | 456 | 41 |
| `0x69` | `ActionExtends` | 455 | 41 |
| `0x3c` | `ActionDefineLocal` | 436 | 35 |
| `0x53` | `ActionNewMethod` | 372 | 35 |
| `0x45` | `ActionTargetPath` | 211 | 33 |
| `0x55` | `ActionEnumerate2` | 210 | 38 |
| `0x64` | `ActionBitRShift` | 203 | 33 |
| `0x61` | `ActionBitOr` | 197 | 34 |
| `0x51` | `ActionDecrement` | 192 | 41 |
| `0x2b` | `ActionCastOp` | 140 | 35 |
| `0x63` | `ActionBitLShift` | 132 | 33 |
| `0x06` | `ActionPlay` | 97 | 7 |
| `0x8c` | `ActionGoToLabel` | 80 | 4 |
| `0x44` | `ActionTypeOf` | 79 | 34 |
| `0x4b` | `ActionToString` | 69 | 30 |
| `0x65` | `ActionBitURShift` | 42 | 14 |
| `0x62` | `ActionBitXor` | 33 | 33 |
| `0x81` | `ActionGotoFrame` | 19 | 7 |
| `0x4a` | `ActionToNumber` | 9 | 9 |
| `0x3b` | `ActionDelete2` | 3 | 2 |
| `0x3f` | `ActionModulo` | 3 | 3 |
| `0x22` | `ActionGetProperty` | 2 | 1 |
| `0x23` | `ActionSetProperty` | 1 | 1 |

### What is absent, and therefore never needs implementing

The absences are as informative as the counts, because each one removes a whole subsystem
from the interpreter:

- `ActionWith` — zero occurrences. No `with` block, so the VM needs a plain scope chain
  (locals, then `this`, then the target timeline, then `_global`) and no dynamic scope
  object stack.
- `ActionTry` and `ActionThrow` — zero occurrences. No exception handling, no unwinding, no
  `finally` block semantics. Runtime errors become logged diagnostics, not AS2-visible
  exceptions.
- `ActionSetTarget` and `ActionSetTarget2` — zero occurrences. No SWF 3 style implicit
  retargeting of the current timeline.
- `ActionGetURL` and `ActionGetURL2` — zero occurrences. Nothing loads an external
  document, opens a browser, or performs `loadMovie` through the URL path. This also
  removes a class of security concern before it arises.
- `ActionWaitForFrame` and `ActionWaitForFrame2` — zero occurrences. No streaming-download
  frame gating.
- `ActionEnumerate` — zero occurrences; only the newer `ActionEnumerate2` appears (210
  records). Only the object-form enumeration is needed.
- The wider SWF 3 and SWF 4 legacy set beyond the handful in the table above:
  `ActionStringAdd`, `ActionStringEquals`, `ActionStringLess`, `ActionMBSubstring`,
  `ActionAsciiToChar`, `ActionCloneSprite`, `ActionStartDrag`, `ActionGotoFrame2`,
  `ActionCall`, and the rest never appear. Vanilla is compiled AS2, not hand-written AS1.
- `ActionGetProperty` (2 records) and `ActionSetProperty` (1 record) appear so rarely that
  the numbered-property path is a curiosity rather than a design constraint; the property
  surface is reached through `ActionGetMember` and `ActionSetMember` by name instead.

## The open-ended part is the host API, not the VM

The sweep resolves 3,382 distinct host API names. That number, not the opcode count, is the
real cost centre, and it is what the phasing controls.

The name is recovered structurally: the record immediately before an
`ActionGetMember`, `ActionSetMember`, `ActionCallMethod`, `ActionCallFunction`,
`ActionGetVariable`, `ActionSetVariable`, `ActionNewMethod`, or `ActionDefineLocal` is
checked for an `ActionPush` whose topmost value is a literal string or a constant-pool
reference, resolved against the block's most recent `ActionConstantPool`. This recovers the
surface without simulating the operand stack. The head of the distribution, as
`name count movies`:

```text
gfx 8094 41, _global 3526 42, Shared 2316 41, prototype 1987 41, ui 1935 41,
NavigationCode 1669 34, io 1596 38, addProperty 1535 34, GameDelegate 1520 38,
length 1513 41, Selection 1104 35, _disabled 1088 34, PlayerInfoCard_mc 973 7,
utils 968 34, _parent 927 41, dispatchEvent 924 34, gotoAndStop 909 39,
ASSetPropFlags 894 41, events 891 34, textField 852 36, Math 847 39, managers 828 34,
EventDispatcher 789 34, GlobalFunc 747 39, controls 738 34, _name 713 41,
Constraints 712 34, setState 697 34, call 689 38, _focused 676 34,
addEventListener 661 34, EntriesA 652 15, MovieClip 630 41, focusIndicator 611 34,
SetText 595 31, _width 589 35, Stage 540 42, iSelectedIndex 539 15, text 538 29,
push 530 41, __width 520 34, thumb 516 18, __set__disabled 504 34, _height 494 36,
ButtonChange 467 29, LoginPage_mc 459 5, _x 452 36, toString 449 41,
InventoryDefines 445 8, setFocus 445 35, gotoAndPlay 422 41, FocusHandler 420 34,
__get__entryList 412 15, _CategoriesList 409 9, x 409 40, _instance 408 34,
initialized 408 39, dispatchEventAndSound 394 33, Components 393 30, __height 390 34,
TextField 382 41, navEquivalent 382 41, Proxy 366 28, track 361 18
```

Three things follow from this distribution.

First, `gfx` (8,094 uses in 41 movies) dominates every game-specific name. Vanilla menus are
built on Scaleform's stock CLIK component library — `gfx.controls`, `gfx.managers`,
`gfx.events`, `gfx.ui`, `gfx.io` — not on bespoke Bethesda ActionScript. Implementing the
component framework once therefore serves nearly every menu, which is what makes phase 3
worth its cost.

Second, the head is short and the tail is long. A few dozen names cover the majority of
uses, while the remaining thousands are per-menu specifics such as `InventoryDefines` (8
movies), `_CategoriesList` (9 movies), `PlayerInfoCard_mc` (7 movies), and `LoginPage_mc` (5
movies). Those are exactly the names that belong to phase 4 and to their owning milestones.

Third, the tally is the work list. Because an unimplemented name becomes a logged no-op plus
a counter, running a menu produces a ranked list of what is missing in that menu. The
project never has to guess what to implement next, and never has to implement the full 3,382
to make progress. This is the concrete answer to the "unbounded second VM" risk: the
unbounded part is made incremental and self-reporting by construction.

## The execution model is class registration, not timeline scripting

`DoInitAction` accounts for 1,127 of the 3,414 blocks, and direct tag inspection with
`openskycli swf info` shows what that means in practice. `inventorymenu.swf` carries 45
`DoInitAction` tags and a single 360-byte frame-1 `DoAction`. `hudmenu.swf` carries 42
`DoInitAction` plus three 13-byte `DefineButton2` tags. Even `book.swf`, one of the smallest
movies, has 5 `DoInitAction` and one 149-byte `DoAction`.

Vanilla menus are therefore class libraries, not timeline scripts. Each `DoInitAction`
defines classes and registers them against a sprite symbol; the tiny frame-1 `DoAction` only
bootstraps. The runtime order that follows is:

1. Run each sprite's `DoInitAction` block, in tag order, before the main timeline advances.
2. Run the main timeline's frame `DoAction`.
3. Instantiate the registered class when its symbol is placed on the display list, and
   dispatch the `construct` event.

The clip-event measurement confirms step 3 and rules out an alternative. Across all 53
movies only three of the nineteen `CLIPEVENTFLAGS` events occur at all: `construct` 122
handlers in 24 movies, `load` 1 handler in 1 movie, and `enterFrame` 1 handler in 1 movie.
All sixteen others are zero — including every mouse and keyboard event (`press`, `release`,
`rollOver`, `rollOut`, `keyPress`, and the rest).

Interaction does not arrive through clip-level event handlers. It arrives through the CLIK
component framework — `EventDispatcher` (789 uses), `addEventListener` (661),
`dispatchEvent` (924), `dispatchEventAndSound` (394), `FocusHandler` (420),
`NavigationCode` (1,669) — and through the host bridge. An input design that routes mouse
and key events into `CLIPACTIONS` handlers would produce a menu that never responds. Input
must instead be delivered to the focused CLIK component through the framework's own focus
and navigation path.

## `GameDelegate` is the engine-to-movie bridge

`GameDelegate` is used 1,520 times across 38 of the 53 movies, alongside `io` (1,596 uses in
38 movies) — Scaleform's `gfx.io` namespace, which is where `GameDelegate` lives. It is
present in essentially every menu that talks to the game.

This is the concrete shape the "GFx-style invoke bridge" required by 8.3.2 must take, and
OpenSky should adopt it rather than invent a bridge of its own. The pattern is symmetric:

- The movie registers named callbacks with the delegate, and the engine invokes them by
  name with arguments — the engine-to-movie direction, used for pushing state such as
  inventory contents, health values, or an activation prompt.
- The movie calls named host functions through the delegate, and the engine handles them —
  the movie-to-engine direction, used for reporting a selection, a confirmation, or a
  close request.

Designing the bridge around the observed `GameDelegate` shape means the vanilla movies work
unmodified. Designing a different bridge would mean the movies call into nothing.

Two caveats. The precise argument-marshalling convention `GameDelegate` uses is not yet
read out of the bytecode; that is a bring-up task for 8.3.2, not a settled fact. And the
delegate is only the data channel — focus, navigation, and sound routing go through the CLIK
managers, which is separate work in the same phase.

## Phased subset plan

| Phase | Scope | Unlocks | Verified by |
|---|---|---|---|
| P1 core VM | All 56 opcodes; scope chain, prototype chain, function calls; ECMA-ish natives | Every class definition in the install loads without hitting a hole | `DoInitAction` sweep: all 1,127 blocks run to completion, 0 unimplemented-opcode hits, 0 budget aborts |
| P2 display objects | `MovieClip`, `TextField`, `Stage`, `Selection`; property surface; timeline control | A menu builds a live display list that renders, including content frame 1 hides | Changed-pixel delta on `book.swf` and `loadingmenu.swf`, which render 0 changed pixels statically today |
| P3 framework + bridge | CLIK and `gfx` component library, focus and navigation, input routing, `GameDelegate` | One vanilla menu opens, navigates, and closes under real input | The 8.3.3 gate: deterministic UI-state plus pixel evidence, `Developer > UI Lab` invoke log and op tally |
| P4 per-menu data APIs | Menu-specific host APIs backed by real game data | Each menu's real content | Deferred to the owning milestone: M12.5 inventory, M13.4 journal, M17.2 dialogue |

### Phase 1 — core virtual machine

Implement all 56 opcodes, not a subset of them. Splitting a 56-entry opcode table across
phases would cost more in partial-execution debugging than implementing the whole table
costs outright, and the absent-opcode list above already removes the expensive subsystems.

Alongside the opcodes, phase 1 needs the language-level natives that the class code itself
depends on: `Object`, `Array`, `String`, `Number`, `Boolean`, `Math` (847 uses),
`ASSetPropFlags` (894 uses in 41 movies), and `Object.registerClass`. The prototype chain
must be real, because `ActionExtends` (455), `ActionInstanceOf` (456), and `ActionCastOp`
(140) all depend on it, as does the `prototype` name itself (1,987 uses in 41 movies).
`addProperty` (1,535 uses) means getter and setter properties are required in phase 1, not
later — the `__get__entryList` and `__set__disabled` names in the distribution head are the
compiler's evidence of that.

Exit criterion: every `DoInitAction` block in all 53 movies runs to completion with zero
unimplemented-opcode hits and zero budget aborts. Host API misses are expected at this
stage and are the phase 2 and 3 work list.

### Phase 2 — display objects and the timeline

Implement `MovieClip`, `TextField`, `Stage`, and `Selection` over the existing display-list
and text machinery from milestone 8.2, plus the property surface the movies actually touch:
`_x` (452), `_y`, `_width` (589), `_height` (494), `_visible`, `_alpha`, `_name` (713),
`_parent` (927), and the CLIK-internal `__width` (520) and `__height` (390) pairs. Timeline
control means `gotoAndStop` (909 uses in 39 movies), `gotoAndPlay` (422), `play`, and
`stop`, which is why `ActionStop` (1,379), `ActionPlay` (97), `ActionGotoFrame` (19), and
`ActionGoToLabel` (80) appear at all.

`ActionGoToLabel` and the string form of `gotoAndStop` have a hard prerequisite: `FrameLabel`
(tag 43) is present in vanilla — `inventorymenu.swf` carries one — and the parser does not
decode it yet. Decoding `FrameLabel` is the first task of phase 2.

Exit criterion: a menu builds a display list that renders. The specific measurement is a
changed-pixel delta against the milestone 8.2.5 baseline for movies that currently change
nothing.

### Phase 3 — CLIK framework, input, and the bridge

Implement enough of the `gfx` component library for a real menu: `EventDispatcher`,
`addEventListener` and `dispatchEvent`, `Constraints` (712), the `FocusHandler` and focus
manager path (`setFocus` 445, `_focused` 676, `focusIndicator` 611), `NavigationCode`
(1,669), and the button and list controls those build on (`setState` 697, `ButtonChange`
467, `thumb` 516, `track` 361). Route real keyboard and mouse input into that focus path,
not into clip events. Implement the `GameDelegate` bridge in both directions.

Exit criterion is the 8.3.3 gate itself: one vanilla menu opens, navigates, and closes under
real input, with deterministic UI-state and pixel evidence, and with `Developer > UI Lab`
exposing movie state, the invoke log, and the unimplemented-API tally.

### Phase 4 — per-menu host data APIs

Deferred by design. `InventoryDefines` (8 movies), `_CategoriesList` (9 movies),
`EntriesA` (15 movies), and `iSelectedIndex` (15 movies) are inventory and list-menu data
contracts that cannot be implemented meaningfully before the engine has inventory data to
put in them. Each such API lands in the milestone that owns its data, and until then it is
a logged no-op with a tally entry — which is exactly the degradation the mechanism is for.

## First targets

For phase 1 and 2 bring-up, the smallest movies come first, because a failure in a 6-block
movie is diagnosable and a failure in a 250-block movie is not:

- `book.swf` — 6 action blocks, 5 `DoInitAction` and one 149-byte `DoAction`. It also
  encodes draws but changes 0 pixels at frame 1 (the alpha-0 `CXFORM` case), so it is a
  clean pass/fail signal for phase 2: pixels change or the ActionScript did not run.
- `loadingmenu.swf` — 10 draws, 37 glyphs, 0 changed pixels today. Same signal, with text.
- `bookmenu.swf` — 0/25/1 place tags, 30 sprites, one filter. Small enough to reason about,
  large enough to exercise a real display list.

For the phase 3 interactive target, and therefore for the 8.3.3 gate, the choice is
`startmenu.swf` (23,376 action records, 23rd of 53 by size). It is a CLIK list menu with
keyboard and mouse navigation, which exercises exactly the framework phase 3 implements; its
entries are structural rather than data-driven, so it needs only a small number of
`GameDelegate` callbacks and almost no phase 4 work; and milestone 8.5.1 already needs a
system menu on a vanilla movie, so the work is not spent twice.

The counter-example is worth stating. `quest_journal.swf` (33,692 records),
`modmanager.swf` (29,383), and `inventorymenu.swf` (24,754) are the three largest AS2
consumers, and all three are poor first targets: they are large, and each is gated on a
phase 4 data contract that does not exist yet. Size ranking is not target ranking.

`hudmenu.swf` (15,364 records, 42 `DoInitAction`) is not an interactive target — a HUD does
not navigate — but it is the natural second phase 3 target because milestone 8.4.2 needs it
and it exercises the engine-to-movie direction of the bridge in isolation.

## Budget and safety posture

The interpreter runs untrusted content. Vanilla movies come from the user's own install, but
mod-supplied movies are an explicit goal of this project, and a script that loops forever
must not take the engine with it.

- Bounded execution: a per-frame record budget and a call-recursion depth cap, both
  configurable and both surfaced in the UI Lab tally. Exceeding either aborts that block
  with a logged diagnostic and continues the frame. The observed shape supports this — the
  largest single block is 5,886 records, so a per-frame budget several orders of magnitude
  above that still catches a runaway immediately.
- Never crash on bad bytecode. The parser already degrades a malformed action stream to a
  warning and stops that stream rather than throwing, matching how the display-list parser
  treats a bad control tag. The interpreter inherits that posture: a type error, a missing
  member, or a jump to an invalid offset is a logged diagnostic and a no-op, never a trap.
- No external reach. `ActionGetURL` and `ActionGetURL2` never appear in vanilla and will not
  be implemented; if a mod movie uses them, they stay a logged no-op. The AS2 runtime has no
  filesystem, network, or process access, and the host API surface is an explicit allowlist
  rather than a bridge to arbitrary engine calls.
- Determinism. `ActionTrace` (522 records) output goes to the engine log and the UI Lab, not
  to the rendered frame.

## Open questions and residual risk

Stated plainly, because none of these are settled by the measurement:

- **The 3,382 host API names are an upper bound with noise, in both directions.** The
  resolution is structural, so it also counts local variable names and ordinary object
  properties that are not host APIs at all, which inflates the number. It equally misses any
  name computed at runtime, which deflates it. The count is a good scale indicator and a
  good priority ranking; it is not an exact API list.
- **The Adobe SWF specification stops at the bytecode.** It defines the opcodes and their
  operands, which is what the 56-opcode table rests on. It does not define the player object
  model — `MovieClip`, `TextField`, `Selection`, `ASSetPropFlags`, `Object.registerClass`,
  prototype semantics. Those come from public ActionScript 2 language and API documentation
  plus observation of the bytecode, which is a weaker source. Phase 1 and 2 carry real
  behavioural uncertainty as a result.
- **The Scaleform GFx extensions have no public specification at all.** The `gfx` namespace,
  `gfx.io.GameDelegate`, and the CLIK component behaviour are documented publicly only as
  component usage, not as a runtime contract. Phase 3 is the least predictable phase, and
  its main mitigation is that the component implementations ship inside the movies as AS2 —
  OpenSky can read what CLIK does from bytecode it already decodes, rather than guess.
- **Constant-pool lifetime is a known Flash subtlety and is not resolved here.**
  `ActionConstantPool` appears 936 times with pools up to 404 entries, and a function defined
  under one pool can be called after another pool has been installed. Getting the pool's
  scope wrong yields silently wrong strings rather than an error, which is the worst failure
  mode. This needs a deliberate test during phase 1 bring-up.
- **`ActionDefineFunction2` register semantics are a correctness trap.** With 10,575
  occurrences and up to 23 registers, the preload and suppress flags that decide which of
  `this`, `arguments`, `super`, `_root`, `_parent`, and `_global` occupy which register must
  be exactly right, or every register index in the body shifts. Wrong here means nothing
  works and nothing obviously errors.
- **Scope of `_global` across a movie stack is undecided.** `_global` has 3,526 uses in 42
  movies, and `ImportAssets2` already shares symbols across movies (`sharedcomponents.swf`,
  the fontlibs). Whether OpenSky runs one virtual machine per movie or one shared machine
  for the whole menu stack changes what `_global` means, and the answer is not derivable
  from the tally. It is a phase 1 design decision that should be made explicitly.
- **Runtime cost is unmeasured.** 533,562 records is a static count, not a per-frame count.
  Nothing yet indicates how many records a menu executes per frame, and the answer only
  arrives when phase 1 runs. Memory grew too: since commit `ea35008` a decoded movie retains
  every frame and every action stream rather than frame 1 alone.
- **A menu can be "running" and still wrong.** Zero unimplemented-op hits does not mean
  correct behaviour, only that nothing was missing. Pixel and UI-state evidence remains the
  gate at every phase, per the project's rule that a green build does not prove a triangle
  appeared.

## Legal position

The interpreter is reimplemented from the public Adobe SWF File Format Specification,
version 19 — chapter 5 "Actions" for `DoAction`, `DoInitAction`, and the `ACTIONRECORD`
tables, and chapter 3 "The display list" for `CLIPACTIONS` and `ClipEventFlags` — together
with observation of the user's own lawfully-owned files, and public ActionScript 2 language
documentation for the object model.

No Scaleform GFx SDK code is used, and no code from any other Flash or SWF player
implementation is copied or adapted. No game data is committed: the sweep output lives in
`logs/swf-action-sweep.log`, which is gitignored, and every unit test uses synthetic
in-code fixtures built by `SWFActionFixture`, never an extracted `.swf`. Movies load from
the user's install at runtime like all other game data.

## References

- Adobe SWF File Format Specification, version 19 — chapter 5 "Actions" (`DoAction` and
  `ACTIONRECORD` p. 63, `DoInitAction` p. 108, per-action tables pp. 64-116); chapter 3
  "The display list" (`CLIPACTIONS` pp. 36-37, `ClipEventFlags` pp. 48-49).
- [SWF container](/formats/swf.md) — tag coverage, the action-tag section, and the full
  vanilla sweep results this document draws on.
- [screen-space UI layer](/rendering/ui.md) — the compositing path the AS2 runtime drives.
- [CLI tools](/tools/cli.md) — `openskycli swf action-sweep`, the command that produced
  every number here.
- Commits `ea35008` (action-record framing) and `989a851` (the inventory sweep).

---
type: Subsystem
title: Papyrus world runtime
description: How the Papyrus VM runs inside the engine loop - main-actor confinement, the fixed-step
  frame hook, the event queue and its budget, instance lifecycle over cell streaming, script state
  in a save, the lazy script library, and the World > Scripts panel.
tags: [engine, papyrus, streaming, save]
---

# Papyrus world runtime

`PapyrusWorldRuntime` puts the [Papyrus VM](/engine/papyrus-vm.md) inside the engine loop. It owns
one VM runtime and one scheduler, plus what the world needs and the core has none of: an instance per
script on each reference, one event queue, and a fixed-step tick run once per drawn frame.

It is confined to the main actor, like the [world state store](/engine/runtime-state.md). Every field
is read and written on the thread that runs `draw(in:)`, so nothing between a streamed cell and its
scripts needs a lock.

An instance key is a `ReferenceKey` plus the script name in lower case. Keys sort by reference, then
by script name. That order makes attach order, event order, and save bytes deterministic.

## Frame hook and fixed step

The renderer calls the world update once per drawn frame. Inside a frame the order is: move the
camera, run the frame handlers (cell streaming and the HUD), advance the game clock, update the world
simulation, then weather, animation, particles, and audio. Scripts run after the clock on purpose, so
a script waking on game time sees this frame's clock.

The frame handler list is ordered and has no removal. The streamer is registered before the HUD,
so it runs first.

Menu pause reaches the VM as a clock, not a branch. A paused frame delivers a delta of exactly zero
and the hook still runs ([menu mode](/engine/menu-mode.md)). The world runtime never reads the wall
clock or a pause flag.

- One fixed step ticks the scheduler, settles what woke, then drains the event queue up to the
  budget. Tests and the offscreen path drive this directly.
- Advancing by a delta adds it to an accumulator and runs whole steps only, so the frame rate never
  changes the simulation. A delta of zero or less does nothing. One advance runs at most 4 steps,
  and the accumulator is then clamped to 4 steps, so a stall of several seconds does not turn into
  minutes of catch-up.

The offscreen renderer drives the hook with the same fixed 1/30 second step it uses for animation,
and never advances the game clock.

## Event queue

There is one first-in, first-out queue for the whole world. An event queued earlier runs no later
than one queued after it. Events are always queued, never run inline, so an attach never re-enters
the VM from inside streaming.

Each instance runs one event at a time. An instance whose handler suspends in a latent call is busy,
and its later events wait, in order, until that handler finishes. Other instances run past it. A
skipped event goes back ahead of the rest of the queue, so the queue never reorders.

A drain stops when the tick has run 32 events, or when it has run 100,000 instructions. The rest
waits for the next tick. 32 events drains a ten-script cell in one step, because an attach queues
three events per instance, and a mass attach carries over instead of stalling a frame. 100,000
instructions is a tenth of one call's budget, so one runaway handler cannot take more of a frame
than one whole call may.

`OnInit` fires once ever per instance. The fired set is saved. A pending set covers the gap between
queuing and running, so a rebuild in between cannot queue a second one. Whether a function exists is
checked with the interpreter's own method lookup, so state priority applies.

## Skips

Bad or unknown input must not stop the world, so these are counted, never faults:

| Reason | When |
| --- | --- |
| `removedScript` | The `VMAD` entry is flagged removed |
| `missingScript` | The script is not in the library and cannot be loaded |
| `instanceCreationFailed` | Making the instance threw |
| `bindingFailed` | A `VMAD` property could not be bound |
| `retiredEventTarget` | The instance was retired before its event ran |
| `undefinedEventFunction` | No script in the chain defines the function. This is the common case |
| `unknownSaveScript` | A saved instance names a script this session cannot make |
| `unknownSaveVariable` | A saved variable does not exist on the instance |

A repeat `OnInit` is also a counted no-op.

## Instances over cell streaming

The [cell streamer](/engine/cell-streaming.md) announces a cell attach, with a flag for a first
integration, and a cell detach. It does not depend on the VM. A scene with no cell location, such as
a door target whose `CELL` failed to resolve, is not announced, because the location is the key
instances are filed under.

Four streaming paths needed a rule:

- A world state rebuild attaches with first integration false, so load events do not fire again.
- A cell staged offscreen during a coverage change announces nothing until the change commits. Cells
  are then announced in sorted order, first integration true only when no scene was replaced at that
  spot. Dropping staged cells announces no detach, because they never attached.
- An interior door transition is a first integration unless it is a rebuild, and detaches the old
  interior only then.
- An exterior door arrival detaches the old interior, but not the scene it replaces at the target
  spot. That scene has the same location key, so detaching it would retire instances the attach
  makes again.

Attach walks the cell's references in sorted order, in two passes. The first makes every missing
instance. The second binds `VMAD` properties once every instance exists, so a property naming
another reference in the same cell gets a live handle. A reference with several scripts is
represented by the instance with the lowest script name. On a first integration each instance gets
`OnInit` (if never fired), `OnCellAttach`, then `OnLoad`.

Detach retires the cell's instances in sorted order: the instance leaves, its queued events drop, and
its suspension records are forgotten.

## Script state in a save

Instance states are sorted by key, and variables by script and name, so an unchanged runtime saves
the same bytes. A restore makes missing instances from the library, so it works before any cell
attaches. The bytes are the `PSCR` chunk ([save chunks](/formats/opensky-save-world-chunks.md)).

Loading restores Papyrus last, after the world state and the game clock. The world state restore
only queues rebuilds, and those rebuilds read the fired `OnInit` set. Restoring that set first is
what stops every script running `OnInit` again on load.

## Lazy script library

Decoding every `.pex` in an install costs far more than a session uses. The library asks a provider
for a script the first time an attach needs it. A script loads with its ancestors, so an inherited
native is found under the script that declares it. Every failure is remembered, so a missing or
broken script is not decoded again on every attach. The app builds the provider over the
[virtual file system](/formats/vfs.md) and the same [form ID resolver](/formats/formid.md) the cells
used. A scene with no file system gets no VM, rather than a VM with an empty library.

## World > Scripts

The `World > Scripts` panel shows instances and the scripts on the interaction target, quest
instances and alias fills ([quest scripts](/engine/papyrus-quests.md)), recent events, the scheduler,
and the native tally. Readouts come from one snapshot, refreshed at 2 Hz.

The scheduler section has pause, step one tick, and burst 20 ticks. A burst is capped at 60. Pause is
checked only at the top of an advance: a paused advance does nothing and builds no backlog. Stepping
ignores it. This pause is separate from menu pause, and either one stops scripts. The last tick
report is kept only from a tick that did work, so the readout never shows a report of zeros. The
destination counts as overridden while paused, and Reset unpauses.

## Stated simplifications

- Objects and arrays are not saved. Their identity is made at run time and means nothing in the
  world, so they save as `None` and restore to the compiled default.
- A persistent reference's instances are never retired, not even by a world space change.
- A reference that first appears in a rebuilt cell gets `OnInit` but no `OnCellAttach` or `OnLoad`,
  because the cell did not attach again.
- The fired `OnInit` set outlives retirement. A reference that leaves and comes back gets fresh
  defaults and no second `OnInit`.
- A latent call whose instance was retired stays in the scheduler and faults when it wakes. This
  keeps retirement cheap instead of scanning the scheduler on every detach.

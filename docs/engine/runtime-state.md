---
type: Subsystem
title: World state store
description: The mutable store that holds every runtime change from plugin data - typed components
  per reference, the failure model, dirty counts and reset, the change journal, the deterministic
  snapshot, how a cell build applies it, how a change reaches the screen, and save and load.
tags: [engine, world, cell-scene, save-state, runtime-state]
---

# World state store

The world state store is the one place runtime changes to plugin data live. Scripts, inventory,
quests, actor values, and many more write to it. It is mutable, so it lives on the main actor, and
it holds no locks. Identity is on the [reference identity](/engine/reference-identity.md) page.

Other pages cover what particular components mean:
[global variables](/engine/global-variables.md), [inventory state](/engine/inventory-state.md),
[quest state](/engine/quest-state.md), [actor value store](/engine/actor-value-store.md), and
[death](/engine/ragdoll.md).

## Components

State is stored as separate typed components per reference, not as one wide record, so a new
feature adds a component without reshaping anything. A reference's delta holds at most one value per
component kind, plus the cell of its most recent change. Some examples:

| Component | Holds |
| --- | --- |
| Enable state | `isEnabled`, over the record header's `initiallyDisabled` flag |
| Transform | A placement, plus the uniform scale `XSCL` holds separately |
| Activation | The activation count, the open marker, and the last activator, for `OnActivate` |
| Deletion | Deleted at runtime. This is not the record header's `deleted` flag |
| Inventory | Every item an owner holds, and its equipped set |
| Spawn | An object the running game placed |
| Quest | One quest's running and completed flags, stages, and objectives |
| Quest aliases | One quest's filled aliases |
| Actor values | Current health, magicka, and stamina, plus the override table |
| Death | Death, the corpse's resting root transform, and whether it was searched |
| Dialogue | How often one response has been said, keyed by its `INFO` |

Adding a component needs a kind, a value type, and an erased case. Every store operation (set,
reset, dirty counts, journal, snapshot) is written against the protocol and the erased value, so none
of it changes.

Writes go through the store and never around it, so the journal, the dirty counts, and the save see
every change, including every script change ([Papyrus
activation](/engine/papyrus-activation.md#the-world-bridge)). Each write passes the reference's
loaded cell. An attributed change rebuilds one cell. An unattributed one rebuilds every loaded cell.
A reference no loaded cell knows stays unattributed. That is the correct fallback, not a guess.

## No operation throws

Writing to an unknown key is not a failure. A reference does not need to be loaded, or even defined
by a plugin, to have state: a script can disable an object in a cell that was never loaded.
Resetting a clean reference is a no-op that returns false. Writing the value already stored does
nothing and journals nothing. This is runtime state, not file parsing, so there is no malformed input
to reject.

## Dirty counts and reset

The dirty count is the number of references that differ from plugin data. Only dirty references have
a delta: clearing the last component removes the key. Counts per cell are kept up to date as writes
happen, so asking for one cell's count is a lookup, not a scan. The cell comes from the caller and is
remembered in the delta, because the store outlives cell eviction. A change with no meaningful cell
is allowed and counted as unattributed.

Reset drops one component, a reference's whole delta, or everything. Baselines are never cached. The
resolved state takes the reference's entry, derives the plugin default from the record again, and
lays the delta over it. So a reset restores whatever the record says now, and the resolved state
reports which slots the delta supplied, so "disabled by a script" and "disabled by the record" stay
different.

Two baseline gaps are known. A `REFR` placement does not decode the record header, so it baselines
as enabled whatever its `initiallyDisabled` flag says. An `ACHR` does carry the flag and respects it.
Neither carries the header's `deleted` flag, so the deletion baseline is always "not deleted". That
flag means the plugin removed the record, which is handled when references are collected.

## The change journal

The journal is an ordered log of every change. The save layer uses it, the Runtime State panel shows
it, and Papyrus needs a causal order for its events. Each entry has a store-wide sequence number
that only grows (starting at 1), the key, the kind, the old and new values, and the cell. The old
value is empty when the slot was clean. The new value is empty for a reset.

A running game changes state forever, so the journal is bounded: 4,096 entries by default, and at
least 1. It is a fixed-size ring, so recording is constant time and memory is fixed. When it is full
the oldest entry is dropped and counted, and sequence numbers keep rising, so a reader can tell
"nothing happened" from "I missed it". Clearing the journal does not reset the numbers, because
clearing the log does not mean the changes never happened.

## The snapshot

The snapshot is a read-only value that holds the dirty references in `ReferenceKey` order, the
global overrides, and the allocator position. It is the only part of the store that crosses to the
cell build queue.

The order makes it useful. The store's dictionaries iterate in no fixed order, so the snapshot sorts
them. Two stores that reached the same end state through different orders of writes give equal
snapshots. The allocator position is included, because two stores that made different numbers of
generated keys are not in the same state.

Each snapshot also carries the journal sequence at capture time. It is not part of equality: it
says when the snapshot was taken, not what state it describes.

## Applying state in a cell build

A cell build takes a snapshot as a parameter ([cell scene](/engine/cell-scene.md)). The snapshot is
taken on the main thread and is read-only, which is why the store never leaves the main actor.

State is applied at exactly one point per build. References are collected and keyed, and then each
one is resolved through its delta. The result is two lists: the index entries, which keep every
reference the plugin placed, and the effective references, which are what gets placed. Objects the
game spawned into the cell join before this step, so one set of rules applies to both. Drawing,
collision, doors, and interaction all read the one effective list. So a moved reference cannot be
drawn in one place and solid in another, and a disabled door cannot be used.

- A reference that is disabled or deleted at runtime is dropped and counted, like a record that
  starts disabled. The build summary names these `runtime-disabled` and `runtime-deleted`.
- A transform override places the reference at the override's position, rotation, and scale.
- Placed actors get the same visibility check. The record flag and the runtime component resolve
  through one state, so enabling a hidden actor at runtime makes it appear.
- The index keeps hidden references. A disabled object still exists and can be found by key.
- Spawned objects are counted apart from authored ones, and the summary checks
  `total + spawned == drawn + skipped`.

Deltas are turned into a lookup table once per build. Looking up by key in the snapshot is a scan,
which is right for one probe and wrong for a loop over every reference.

## Making a change visible

Each built cell records the snapshot sequence it was built from. A change raises a mutation sequence
for the cell it was attributed to. A loaded cell is current while its build sequence is at least its
mutation sequence. That one comparison drives everything:

- A change to a loaded cell queues a rebuild. The cell stays loaded and the old scene keeps drawing
  until the new one is ready. Rebuilds wait behind first loads, so a new cell still arrives from the
  center outward.
- A change during a build for the same cell: the running build is always used, so the cell draws as
  early as possible. If it turns out older than the change, a rebuild is queued with a fresh
  snapshot. This also works around the build runner merging a coordinate that is still pending.
- A rebuild builds the whole cell from plugin bytes plus the current snapshot. Doing it twice is the
  same as doing it once: there is no delta to apply twice or lose.

Three results follow from state living only in the store:

- Unloading a cell changes no state, and a pending rebuild for an unloaded cell is dropped. A
  returning cell rebuilds from plugin bytes and the current snapshot, which applies its delta again.
- An unattributed change rebuilds every loaded cell. That is correct first. The way to narrow it is
  to attribute the write.
- An interior has no way to build alone. It only arrives as a door destination. So its rebuild runs
  the same door transition again with a fresh snapshot and no camera, so the player stays where they
  stand ([interiors](/engine/interiors.md)).

There is no patching of single instances: a rebuild is a whole cell.

## Save and load

The snapshot is exactly what a save writes, and restoring it is exactly what a load does. The byte
layout is on the [OpenSky save container](/formats/opensky-save.md), the
[actor chunks](/formats/opensky-save-actor-chunks.md), and the
[world chunks](/formats/opensky-save-world-chunks.md) pages.

Saving writes the live snapshot with a load-order fingerprint, built from each plugin's `HEDR`.
Loading decodes a slot, can check the fingerprint, and restores the snapshot. Restoring replaces
every delta and every global override, takes the allocator position so new generated keys never
collide with saved ones, and journals nothing: a load is not a series of meaningful changes. It then
fires one unattributed change, so every loaded cell rebuilds, and one global change, so weather and
other readers take the restored values.

Papyrus state is restored last, after the snapshot and the clock. The rebuild queued by the restore
attaches scripts on a later streaming update and checks the VM's record of which `OnInit` events
already ran. Restoring that record before any rebuild attach reads it stops every script from
running `OnInit` again on load.

A round trip gives the same deltas, maybe in a different store, driving the same cells to rebuild.
The save format is deterministic, so a test can compare the restored snapshot to the original by
equality.

## Controls

World > Runtime State:

- Inspect: loaded reference count, dirty count, allocator position, dropped journal entries, and the
  newest journal entries. Component and global changes are shown in one list, merged by their shared
  sequence number, so the order is the real order of the writes.
- Change: a target (a typed hex form ID, or the current interaction target), and Disable, Enable, and
  Nudge.
- Reset: reset the target or everything.
- Save: a slot name, Save, and Load. The readout lists the slots on disk and the last result,
  including a failed load's error text.

The Time, Globals, and Conditions sections are on the [global variables](/engine/global-variables.md)
page. The destination counts as changed while any reference is dirty, any global is overridden, or
the timescale is not its default. The sidebar reset clears all three.

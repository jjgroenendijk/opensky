---
type: Subsystem
title: Reference identity
description: Why a raw FormID cannot identify a placed object for a session, the ReferenceKey that
  does, its total order, the generated key allocator, the per-cell reference index, and the
  identity of objects the running game spawns.
tags: [engine, world, identity, cell-scene, save-state]
---

# Reference identity

Every placed object needs an identity that stays the same for the whole session. The state stored
against it is on the [world state store](/engine/runtime-state.md) page.

## Why a raw FormID is not enough

A form ID depends on the load order. Its top byte indexes the defining plugin's own master list
([FormID](/formats/formid.md)), so one raw value means different objects in different plugins. A
resolved form ID pairs the plugin name with the object ID, but the name is spelled however the
`TES4` `MAST` field spelled it, and plugin file names ignore case on the game's original platform.
So neither is safe as a dictionary key for a session.

## ReferenceKey

`ReferenceKey` has two cases:

- `.plugin(name:objectID:)`: a reference a plugin defines. The name is always made lower case when
  the key is built, so identity does not depend on `MAST` spelling or file system case.
- `.generated(UInt64)`: an object created at runtime, such as a dropped item, that no plugin
  defines.

The two cannot collide: they are separate cases, not number ranges that could overlap. The null form
ID resolves to no key, meaning "no reference".

The player's key is `.generated(0)`. The allocator reserves 0 and never hands it out. The player has
no decoded record here, but Papyrus needs one stable identity for it, as the activator of an
`OnActivate` and the `akActionRef` a script receives. The vanilla `Skyrim.esm:000014` player
reference was rejected for three reasons. It names a record OpenSky does not decode. It would be
wrong for a load order without that plugin. And it would make the player look like an ordinary
streamed reference that a cell build might try to draw. The sentinel sorts after every plugin key,
needs no plugin, and survives the save file's generated-key tag unchanged. No index entry exists for
this key, so no cell build sees it
([Papyrus activation](/engine/papyrus-activation.md#the-players-handle)).

## Order

Keys have a total order, which saving and every stable walk rely on:

1. Every `.plugin` key comes before every `.generated` key.
2. `.plugin` keys order by the lower-case name, then by object ID.
3. `.generated` keys order by number.

Dictionary order is not fixed, so every walk over a whole index that must be stable (saving, the
inspection UI) uses the sorted keys.

## Generated keys

The allocator hands out `.generated` keys in sequence. Its only state is the next number, starting
at 1. The same series of allocations gives the same keys, which makes a save reproducible. The next
number is exactly what a save stores, and a restored session continues from it. The world state
store owns the allocator, because generated identity outlives every cell, like the state beside it.

## The reference index

Each cell has a reference index, built from its decoded placement records. Each entry pairs:

- the `ReferenceKey`;
- the raw form ID as the plugin spelled it, because collision rays and interaction data address
  references by raw form ID, so both directions must work;
- whether the reference is persistent;
- the decoded record: a `REFR` or an `ACHR`.

The index can be searched by key or by raw form ID. Both tables are built once. Duplicate keys keep
the last one, matching how the exterior reference merge removes duplicates, so a worldspace
persistent record that overrides a local placement of the same object leaves one entry.

A cell stores placements in two groups: persistent children and temporary children. Drawing treats
both alike, but the index needs the difference. A reference from a local temporary group is
temporary. Everything else in the cell's final set is persistent, including worldspace persistent
children merged into an exterior cell by position, because they outlive the one cell they draw in. An
`ACHR` takes its tag from the group it came from. A record with a null or unresolvable form ID has no
identity and is left out, not given a placeholder.

The index is built once per cell on the build queue ([cell streaming](/engine/cell-streaming.md)) and
travels with the built cell as a read-only value. It holds only value types, so it crosses to the
main thread without locks. It is rebuilt on every load and dropped on eviction.

## Looking a reference up

The cell composition searches the loaded exterior cells in turn and returns the first entry found.
There are only a few loaded cells, and each lookup is a dictionary hit. The streamer adds the
interior-first rule the rest of its queries follow: when an interior is active, it replaces the
exterior composition and answers alone ([interiors](/engine/interiors.md)).

## Spawned objects

The running game places objects no plugin defines: a dropped item now, and later a summon or a
`PlaceAtMe` result. A spawn is one more component, not a list beside the store. So the whole store
handles it unchanged: the journal records a spawn like a `Disable()`, the snapshot orders it, the save
writes it, and the cell it lands in rebuilds.

The spawn component holds the base record, the cell, the placement, the scale, and the stack count.
It does not change a plugin placement: it is the placement, and only a generated key carries it. Its
initializer turns a count below one into one, and a scale that is not a positive finite number into
one, because the save decoder uses it and a broken file must degrade, not fail the load.

The cell is in the component, not taken from the delta's cell. The delta's cell records where the
most recent change happened, and every write overwrites it. That is right for dirty counts and wrong
for "where does this object exist": moving a dropped item could otherwise strand it in the wrong
cell.

### A form ID for a spawn

Everything below the index (collision rays, interaction data, the draw sort key) addresses a
placement by raw form ID, so a spawn needs one. The generated number goes into mod index `0xFF`:
`.generated(1)` becomes `FF000001`.

`0xFF` is safe by construction. A plugin's records are numbered by its load-order position, which is
one byte, so a load order holds at most `0xFE` plugins and no plugin record has `0xFF`. Bethesda's
own save format uses the same index for objects a save created, which agrees with this reasoning
without being its source. A number past `00FFFFFF` has no form ID left, so the build drops the object
and counts it, instead of giving two objects one ID. That needs 16.7 million spawns in one session.

### How a build places a spawn

The build walks the snapshot's entries, already in key order, keeps the spawns in this cell, and
turns each into an ordinary placement and index entry. They are persistent, because the store holds
them, not the cell: a dropped item is still there when you come back.

After that a spawn is the same as an authored placement. The same state pass moves or hides it, the
same code draws it, makes it solid, and makes it takeable. That is why dropping reuses the component
system instead of a separate list of runtime objects, and why a dropped item's mesh and collision
cannot disagree.

## Moved references

`MoveTo` can send a plugin reference to a cell other than the one its plugin places it in. The
opening quest does this: Ralof stands in Helgen and Ulfric in an interior, and both move to the
cart on the road. A transform override alone cannot do that, because a cell build draws only the
records its own cell holds, and an exterior persistent record is drawn by the cell its plugin
position falls in.

So `MoveTo` writes two components: the transform override, and a relocation that names the cell
that draws the reference now. A build then follows one rule:

- a reference whose relocation names another cell is left out of its plugin cell;
- a reference whose relocation names this cell joins this cell's build, with the record read
  from a FormID index over the whole plugin, because its plugin cell may not be loaded.

Moving a reference back to its plugin cell drops the relocation. The same index answers `MoveTo`
for a reference no loaded cell holds: its state is the plugin record with this session's deltas on
top. The save writes relocations in the `RLOC` chunk ([save format](/formats/opensky-save.md)).

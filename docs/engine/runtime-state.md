---
type: Subsystem
title: Runtime reference identity
description: Session-stable ReferenceKey identity, the per-cell RuntimeReferenceIndex, the
  generated-object allocator, and where runtime-state ownership sits relative to cells.
tags: [engine, world, identity, cell-scene, save-state]
timestamp: 2026-07-27T00:00:00Z
---

# Runtime reference identity

Issue #158 (milestone M10.1, item 10.1.1) gives every placed object a session-stable
identity that survives the fact that a raw `FormID` does not. This page documents that
identity scheme, the per-cell index built from it, and the ownership seam it leaves for
later M10.1 work.

## Why raw FormID cannot be the key

A `FormID` is load-order relative: the top byte is an index into the defining plugin's own
master list (see [FormID + TES4 plugin header](/formats/formid.md)), so the same raw value
means different objects depending on which plugin's records it is found in. `ResolvedFormID`
fixes that by pairing plugin name with object ID, but the plugin name still comes from
whatever spelling the TES4 `MAST` field used, and plugin file names are case-insensitive on
the game's original platform. Neither type is safe to use as a persistent dictionary key
across a session. Impl: `opensky/Formats/ESM/FormID.swift`.

## `ReferenceKey`

`ReferenceKey` (`opensky/Formats/ESM/ReferenceKey.swift`) is the persistent identity type.
It is a two-case enum:

* `.plugin(name: String, objectID: UInt32)` — a plugin-defined reference. `name` is always
  lowercased at construction, through `init(resolved:)` or `resolve(_:using:)`, so identity
  is stable regardless of `MAST` spelling or filesystem case.
* `.generated(UInt64)` — a runtime-created object, such as a dropped item or a summon, that
  no plugin defines.

Collision between the two namespaces is impossible by construction: they are distinct cases
of the same enum, not overlapping numeric ranges that could alias.

`ReferenceKey.resolve(_:using:)` takes a raw `FormID` and a `FormIDResolver` and returns
`nil` for the null FormID, which means "no reference."

### Total order

`ReferenceKey` conforms to `Comparable` with a documented total order that downstream
save and state work (10.1.2, 10.1.4) relies on for deterministic iteration:

1. Every `.plugin` key sorts before every `.generated` key.
2. `.plugin` keys order by the already-lowercased `name` first, then by `objectID`
   ascending.
3. `.generated` keys order by sequence number ascending.

`RuntimeReferenceIndex.sortedKeys()` and `sortedEntries()` are the only sanctioned way to
walk a whole index, because dictionary iteration order is not deterministic and every
caller that needs a stable walk — save serialization and inspection UI among them — needs
this order.

## `GeneratedReferenceAllocator`

`GeneratedReferenceAllocator` hands out `.generated` keys in sequence. It is a value type
with exactly one piece of state, `nextSequence: UInt64`, starting at 1 (0 is reserved as a
sentinel and never allocated). Given the same sequence of allocation events it produces the
same keys, which is what makes a saved game reproducible: `nextSequence` is exactly the
state a future save must persist, and `init(nextSequence:)` is how a restored session
resumes allocating from where it left off. `allocate()` is the only mutating operation and
returns the freshly minted `ReferenceKey`.

This issue ships the allocator as a standalone value type. It does not yet live anywhere —
see "Ownership: where identity state lives" below.

## `RuntimeReferenceIndex`

`RuntimeReferenceIndex` (`opensky/World/RuntimeReferenceIndex.swift`) is the per-cell lookup
built from decoded placement records. It holds `RuntimeReferenceEntry` values, each pairing:

* `key: ReferenceKey` — the session-stable identity.
* `formID: FormID` — the raw, load-order-relative FormID exactly as the plugin spelled it,
  retained because collision raycasts and interaction metadata address references by raw
  FormID, so both lookup directions need to work.
* `isPersistent: Bool` — whether the record came from a cell persistent children group or
  from the worldspace persistent CELL.
* `record: RuntimeReferenceRecord` — the decoded record itself, either `.reference
  (PlacedReference)` for a REFR or `.actor(PlacedActor)` for an ACHR.

The index is addressable both by `ReferenceKey` (`subscript(key:)`) and by raw `FormID`
(`entry(for:)`), backed by two dictionaries built once at `init(entries:)`. Duplicate keys
resolve last-writer-wins, matching the FormID dedupe the exterior reference merge already
performs, so a worldspace-persistent record overriding a local placement of the same object
leaves exactly one entry behind. `RuntimeReferenceIndex.empty` is the value cells built
without reference retention — synthetic render tests — use instead of an optional field.

### Persistent versus temporary

A cell stores placements in two children groups, `.cellPersistentChildren` and
`.cellTemporaryChildren`. `CellSceneBuilder`'s reference collection
(`opensky/World/CellSceneBuilderReferences.swift`) tags each REFR with the group it came
from while collecting. The render path treats both groups alike and flattens them, but the
runtime index needs the distinction: a reference decoded from a local temporary group is
temporary, and everything else in the cell's final placed set — including worldspace
persistent children merged into an exterior cell by position — is persistent, because it
outlives the streaming lifetime of the one cell it happens to be rendered in. `ACHR`
records (actors) carry their persistence tag directly from the group they were collected
from.

A record with a null or otherwise unresolvable FormID has no runtime identity and is left
out of the index rather than given a placeholder key.

### Build and lifetime

`RuntimeReferenceIndex` is assembled once, per cell, on `CellSceneBuilder`'s serial build
queue (see [Cell streaming](/engine/cell-streaming.md)), then carried as an immutable value
in `CellScene.references`. Because it is immutable after construction and holds only value
types, it crosses to the main thread as part of the `CellScene` value without locking, the
same handoff pattern the rest of cell scene state already uses. The index is rebuilt on
every cell load and dropped on eviction: its lifetime is exactly the owning cell's.

## Query surface

Two layers query the index by the time a cell is resident:

* `CellSceneComposition.referenceEntry(key:)` / `referenceEntry(formID:)`
  (`opensky/World/CellSceneComposition.swift`) scan the composition's resident exterior
  cells linearly — the same shape as the pre-existing `interaction(reference:)` lookup —
  and return the first entry found. The scan is over a handful of resident cells, so the
  linear walk is cheap; each per-cell lookup is a dictionary hit.
* `CellStreamer.referenceEntry(formID:)` / `referenceEntry(key:)`
  (`opensky/World/CellStreamerInteraction.swift`) add the interior-scene-first fallback that
  the rest of the streamer's query surface already follows: when an interior scene is
  active it replaces the exterior composition entirely and answers alone, matching
  [Interior door transitions](/engine/interiors.md); otherwise the call forwards to
  `CellSceneComposition`.

## Ownership: where identity state lives

This issue draws the ownership line that issue #159 builds on:

* State keyed per cell — the `RuntimeReferenceIndex` itself — lives with `CellScene`,
  rebuilt on every cell load and dropped on eviction, same as the rest of a cell's decoded
  content.
* State that must outlive any single cell does not live here. That includes the
  generated-object allocator and the mutable reference state (position, deletion, and so
  on) planned for 10.1.2. That state belongs above the cell, in a store that follows the
  `WeatherStore` pattern already used for weather (`opensky/World/WeatherStore.swift`):
  queue-confined build, an immutable value handed off to the render/main thread, no locks.

This issue ships `GeneratedReferenceAllocator` as a standalone value type and deliberately
does not build that store — that is the next issue's work, tracked in GitHub rather than
here.

## Related pages

* [FormID + TES4 plugin header](/formats/formid.md) — the raw and resolved FormID types
  `ReferenceKey` normalizes.
* [Cell scene build](/engine/cell-scene.md) — how REFR/ACHR placements are decoded before
  reference collection tags and indexes them.
* [Cell streaming](/engine/cell-streaming.md) — the serial build queue the index is
  assembled on, and the residency/eviction lifecycle that bounds it.
* [Interaction targeting](/engine/interaction.md) — the raw-FormID lookup pattern
  `referenceEntry(formID:)` follows, and the interior-first fallback it shares with
  `interaction(reference:)`.

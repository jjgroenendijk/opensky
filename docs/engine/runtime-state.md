---
type: Subsystem
title: Runtime reference identity and world state
description: Session-stable ReferenceKey identity, the per-cell RuntimeReferenceIndex, the
  generated-object allocator, and the mutable WorldStateStore that holds every runtime
  deviation from plugin data.
tags: [engine, world, identity, cell-scene, save-state]
timestamp: 2026-07-30T00:00:00Z
---

# Runtime reference identity and world state

Issue #158 (milestone M10.1, item 10.1.1) gives every placed object a session-stable
identity that survives the fact that a raw `FormID` does not. Issue #159 (item 10.1.2)
builds the mutable store that keys runtime state by that identity. This page documents the
identity scheme, the per-cell index built from it, and the store above both.

## Contents

* Why raw FormID cannot be the key
* `ReferenceKey`, its total order, and `GeneratedReferenceAllocator`
* `RuntimeReferenceIndex` — the per-cell, immutable lookup
* Query surface
* Ownership: where identity state lives
* `WorldStateStore` — components, dirty tracking, reset, journal, snapshot
* Runtime global variables and the value-lookup seam
* Applying state during a cell build
* Making a mutation visible: snapshot capture and cell rebuilds
* Save and load: the snapshot through `OpenSkySaveStore`
* Verification — `World > Runtime State` and the M10.1 acceptance record
* Verification — the M10.2 panel surfaces and the M10 acceptance record

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

### The player key

`ReferenceKey.player` is `.generated(0)`, the sentinel the allocator reserves and never
hands out (issue #172). The player is not a plugin reference in this engine — no record is
decoded for it — but Papyrus needs one stable identity for it, because the player is the
activator stored in `ReferenceActivationState.lastActivator` and the `akActionRef` handed
to script code. The reasoning behind picking the sentinel over the vanilla
`Skyrim.esm:000014` reference is in [Papyrus virtual machine](/engine/papyrus-vm.md).

Nothing resolves a `RuntimeReferenceEntry` for this key, so it never appears in a
`RuntimeReferenceIndex` and a cell build never sees it. It is an identity for attribution
and for object handles, not a drawable reference.

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

Issue #158 shipped the allocator as a standalone value type. Issue #159 gave it an owner:
`WorldStateStore` holds one instance and hands out keys through `allocateGeneratedKey()`,
because generated identity outlives every cell exactly like the deltas beside it.

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

Issue #158 drew the ownership line that issue #159 builds on:

* State keyed per cell — the `RuntimeReferenceIndex` itself — lives with `CellScene`,
  rebuilt on every cell load and dropped on eviction, same as the rest of a cell's decoded
  content.
* State that must outlive any single cell does not live here. That includes the
  generated-object allocator and the mutable reference state (position, deletion, and so
  on) planned for 10.1.2. That state belongs above the cell, in a store that follows the
  `WeatherStore` pattern already used for weather (`opensky/World/WeatherStore.swift`):
  queue-confined build, an immutable value handed off to the render/main thread, no locks.

`WorldStateStore` is that store, and the rest of this page documents it. It departs from the
`WeatherStore` pattern in one way: weather state is built once on a queue and read as an
immutable value, whereas world state is mutable for the whole session. The handoff shape
survives the difference — the store itself never leaves the main actor, and the immutable
`WorldStateSnapshot` is what crosses to the build queue.

## `WorldStateStore`

`WorldStateStore` (`opensky/World/WorldStateStore.swift`) is the single place runtime
deviations from plugin data live: the substrate Papyrus (M11), inventory (M12) and quests
(M13) mutate. Unlike `WeatherStore`, `SoundRecordStore` and `MusicRecordStore` — immutable
read-only indices built once from an `ESMFile` and readable from any thread — this store is
mutable, so it is `@MainActor`, owned alongside `CellStreamer`, and holds no locks.

### Typed component deltas

Runtime state is stored as separate typed components per reference rather than one wide
state blob, so a later milestone adds inventory or actor values without reshaping anything.
The pieces (`opensky/World/WorldStateComponents.swift`):

* `WorldStateComponentKind` — the slot identity, one case per component.
* `WorldStateComponent` — the protocol a component value type conforms to, supplying its
  kind and the two erasure members (`erased`, `init?(erased:)`).
* `WorldStateComponentValue` — the erased carrier the delta stores and the journal records.
* `ReferenceStateDelta` — every deviation for one reference: at most one value per kind,
  plus the cell the most recent mutation was recorded under.

The initial component set:

| Component | Kind | Holds |
| --- | --- | --- |
| `ReferenceEnableState` | `.enableState` | `isEnabled`, overriding the record header's `initiallyDisabled` flag |
| `ReferenceTransformOverride` | `.transform` | a `PlacedReference.Placement` plus the uniform `scale` XSCL carries separately |
| `ReferenceActivationState` | `.activation` | `activationCount`, the `isOpen` marker, and `lastActivator` for M11's `OnActivate` |
| `ReferenceDeletionState` | `.deletion` | `isDeleted` at runtime, which is not the record header's `deleted` flag |

`ReferenceActivationState` has a production writer since issue #172: the Papyrus activation
bridge subscribes to `CellStreamer.onInteraction`, maps the event's `FormID` to a
`ReferenceKey`, and writes `activated(by:togglesOpen:)` with `ReferenceKey.player` as the
activator. `togglesOpen` is set only for a door-style `open` action, so `isOpen` tracks
doors and containers while a plain activation only bumps the count. Papyrus natives write
the other three components through the same seam
(`PapyrusWorldBridge`, [Papyrus virtual machine](/engine/papyrus-vm.md)); nothing writes
around the store, so the journal, the dirty counts and the save see every script mutation.

Every one of those writes passes the reference's resident `CellSceneLocation`, which the
bridge asks the streamer for. That narrowing matters: an attributed mutation rebuilds one
cell, while an unattributed one rebuilds every resident cell (see
[Making a mutation visible](#making-a-mutation-visible-snapshot-capture-and-cell-rebuilds)).
A reference no resident cell knows stays unattributed, which is the correct fallback rather
than a guess.

Adding a component in a later milestone means adding a `WorldStateComponentKind` case, a
conforming value type and a `WorldStateComponentValue` case. Every store operation — set,
reset, dirty tracking, journalling, snapshot — is written against the protocol and the
erased value, so none of it changes.

### Failure model

No operation on the store throws, and this is a deliberate decision rather than an
oversight. Mutating an unknown key is not a failure: a reference need not be resident, or
even plugin defined, for state to be recorded against it, because a script can disable an
object in a cell that has never been loaded. Resetting a clean reference is a no-op that
reports `false`. This is runtime state, not file parsing; there is no malformed input to
reject. Writing a value equal to the one already stored is likewise a no-op — nothing is
journalled, and `set` returns `false`.

### Dirty tracking and reset

`dirtyCount` is the number of references deviating from plugin data, and only dirty
references have a stored delta at all: clearing the last component removes the key. Cells
are tracked incrementally in a `[CellSceneLocation: Int]` (which is why `CellSceneLocation`
is `Hashable`), so `dirtyCount(in:)` is a dictionary lookup rather than a scan. The cell is
supplied by the caller at mutation time and remembered in the delta, because the store
outlives cell eviction and the cell may be long gone by the time a sidebar asks for counts.
A mutation with no meaningful cell is allowed and shows up in `unattributedDirtyCount`.

`reset(_:for:)` drops one component and `reset(_:)` drops a reference's whole delta;
`resetAll()` empties the store. Baselines are never cached: `resolvedState(for:)` takes the
`RuntimeReferenceEntry` from the index, re-derives the plugin default from the decoded
record, and lays the delta over it (`ReferenceState`,
`opensky/World/ReferenceState.swift`). A reset therefore restores whatever the record now
says, and `ReferenceState.overriddenKinds` reports which slots the delta supplied, so
"disabled by a script" stays distinguishable from "disabled by the record".

Two baseline gaps are deliberate. `PlacedReference` does not decode the record header, so a
REFR baselines as enabled regardless of its `initiallyDisabled` flag; `PlacedActor` does
carry the flag and is honoured. Neither placement type carries the header's `deleted` flag,
so the deletion baseline is always "not deleted" — that flag means the plugin removed the
record, which is a load-time concern and is filtered during reference collection.

### Change journal

`WorldStateJournal` (`opensky/World/WorldStateJournal.swift`) is an ordered log of every
mutation, not a debug aid: save serialization (10.1.4) replays it to know what changed, the
sidebar readout (10.1.5) shows it, and Papyrus needs a causal order for the events it fires.
Each `WorldStateJournalEntry` carries a store-wide monotonic `sequence` (starting at 1), the
key, the kind, the old and new erased values, and the cell. `oldValue` is nil when the slot
was clean; `newValue` is nil when the mutation was a reset.

The journal is bounded, because a running game mutates state forever and an unbounded log is
a leak with a slow fuse. The cap is `WorldStateJournal.defaultCapacity`, **4096 entries**,
injectable through `WorldStateStore(journalCapacity:)` and clamped to at least 1 rather than
rejected — journalling must never be the thing that fails a mutation. Storage is a
fixed-size ring, so recording is O(1) and memory is bounded at construction. Once the window
is full the oldest entry is dropped, `droppedJournalEntryCount` counts the losses, and
sequence numbers keep climbing so a consumer can tell "nothing happened" from "I missed it".
`clearJournal()` empties the window without resetting sequence numbering, because clearing
the log is not a claim that the mutations never happened.

### Deterministic snapshot

`snapshot()` returns a `WorldStateSnapshot` (`opensky/World/WorldStateSnapshot.swift`): an
immutable `Sendable` value holding dirty references in `ReferenceKey`'s total order, plus
the allocator's `nextGeneratedSequence`. It is the only part of the store that crosses to
the serial build queue.

Ordering is what makes it useful. The store's backing dictionaries iterate
nondeterministically, so the snapshot flattens them through `sortedKeys()`-style ordering;
two stores that reached the same end state through different mutation orders produce equal
snapshots, and `WorldStateSnapshot` is `Equatable` so that is directly testable. Mutation
history is deliberately absent from the snapshot — the journal is the separate, bounded,
order-dependent product of the same store. Allocator position is included, because two
stores that minted different numbers of generated keys are not in the same end state.

## Runtime global variables and the value-lookup seam

Issue #165 (item 10.2.2) adds the second kind of mutable state the store holds: global
variables. A [GLOB record](/formats/records.md) authors a name, a declared numeric type and
a default value; a session then writes over that default, and conditions, scripts and the
game clock must all read whatever the session last wrote.

### Why globals are a sibling map, not a component

A global is not placed anywhere. It has no cell, no transform and no plugin baseline that a
cell build re-derives, so modelling it as another `WorldStateComponentKind` on a
`ReferenceKey` would put a value with none of a reference's properties into the type that
exists to describe them — and it would have written a new component tag into the `RDLT` save
chunk, where an unknown tag is a hard error rather than a skip, making the change
non-additive for older builds.

The store therefore keeps `[ReferenceKey: GlobalValue]` beside `[ReferenceKey:
ReferenceStateDelta]`. The key is still a `ReferenceKey` — the GLOB record's own,
resolved through the defining plugin's master list — so identity, ordering and save
encoding are shared with references and nothing new had to be invented for them.

### Typed values and the rounding rule

`GlobalValue` (`opensky/Formats/ESM/Records/Global.swift`) pairs a `Float` with the FNAM
`Global.ValueType`. Every construction coerces the number onto the type, so a short or long
global can never hold a fraction no matter who wrote it — Papyrus, a console command, or a
decoded save. Float globals pass through untouched.

The rounding rule is **half away from zero**: 3.7 becomes 4, -2.5 becomes -3. No open spec
states which rule the original engine used, so this is OpenSky's documented choice. It was
picked over truncation toward zero because truncation makes accumulation wrong in a way
players notice: adding 0.6 ten times to a short global lands on 0 under truncation and on 6
under rounding. Non-finite input to an integer type becomes 0 rather than propagating a NaN
into comparisons that must be total, and nothing is clamped to 16 or 32 bits, because FLTV
is a float on disk and clamping would discard values a mod can legitimately author.

### Mutation, reset and the journal

* `setGlobal(_:type:for:)` and `setGlobal(_:formID:defaults:)` write a value, the second
  taking the declared type and the key from a `GlobalStore`. Writing the value already
  stored is a no-op that reports `false`, exactly like a component write.
* `resetGlobal(for:)` removes the override, so the global reads its plugin default again; an
  empty map means nothing to snapshot and nothing to save. `resetAllGlobals()` clears them
  in `ReferenceKey` order so the log stays deterministic.
* Every write and reset records a `WorldStateGlobalJournalEntry` — sequence, key, old value,
  new value — in its own bounded window inside `WorldStateJournal`, sharing the one
  monotonic sequence counter with the component log. Interleaving the two logs by `sequence`
  reproduces the real causal order, which is what Papyrus and the save layer need;
  `WorldStateJournalEntry` itself was left exactly as it was, since its `kind` describes a
  component slot a global does not have.
* Global writes fire `onGlobalMutation`, **not** `onMutation`. `onMutation` drives cell
  rebuilds, and a global changes a number rather than a scene: routing the game clock's
  per-frame `GameHour` write through it would rebuild the whole resident grid every frame.

### The lookup seam

`GlobalResolution` (`opensky/World/GlobalStore.swift`) is the one place anything asks what a
global is worth. It pairs a `GlobalStore` of plugin defaults with a set of runtime
overrides, and its resolution order is fixed and total: this session's override wins, the
plugin default is the answer otherwise, and `nil` means the FormID names no global the store
knows. `WorldStateStore.globalResolution(defaults:)` builds one from the live store;
`GlobalResolution(defaults:snapshot:)` builds an equivalent one from a `WorldStateSnapshot`,
so a consumer running off the main actor gets the same answers without reaching into the
store.

| call | for |
| ---- | --- |
| `value(for:)` / `value(editorID:)` | the value with its declared type |
| `floatValue(for:)` / `floatValue(editorID:)` | the number alone — the game clock's `TimeScale` read (issue #164) |
| `comparisonValue(_:)` | the right-hand side of a CTDA comparison (issue #251) |
| `isOverridden(_:)` | whether the session has written this global |

Issue #164 threads the [game clock](/engine/game-clock.md) through this seam: a resolution
built with a clock (`globalResolution(defaults:clock:)`) answers the five vanilla time
globals from the clock ahead of any override, and `setGlobal(_:formID:defaults:)` on one of
those editor IDs redirects into the clock through `onTimeGlobalWrite` — journalling through
the globals ring, storing no override, and deliberately not firing `onGlobalMutation` so a
time scrub cannot reroll the weather. The authority rule and its rationale live on the game
clock page.

`comparisonValue(_:)` takes the `Condition.ComparisonValue` the
[CTDA decoder](/formats/conditions.md) produces: a `.value` literal passes through
unchanged, a `.global` operand resolves through the store. A `nil` result means the
condition references a global nothing defines, which the evaluator must treat as
unevaluatable rather than as a comparison against zero.

### The condition evaluator above the seam

Issue #251 (item 10.2.4) built that evaluator, and it is the seam's first
non-trivial consumer. `ConditionEvaluator` (`opensky/World/ConditionEvaluator.swift`,
with its function registry and tally in the sibling `Condition*.swift` files) takes
the decoded [CTDA conditions](/formats/conditions.md) and answers whether a list is
true right now. It lives under `opensky/World/` rather than beside the decoder in
`opensky/Formats/` for the reason the split exists at all: answering a condition
needs live state, and a format parser must not be able to reach live state.

That state arrives as one value, `ConditionContext`, assembled from four things this
page already documents plus one it does not:

* `globals: GlobalResolution` — the seam above, so a condition sees this session's
  overrides, the plugin defaults, and the clock-projected time globals in exactly
  the order the seam defines.
* `clock: GameClock?` — optional, because a context with no world running is a real
  case (an inspector, a test). The time functions report a missing clock rather than
  guessing at one.
* `references: RuntimeReferenceIndex` — what the Reference run-on looks a raw FormID
  up in, and where a `ReferenceKey` becomes the entry a function reads a base form
  off.
* `subject` and `target: ReferenceKey?` — which references the Subject and Target
  run-ons name. The CTDA `swapSubjectAndTarget` flag is applied during that
  resolution.
* `random: ConditionRandom` — a seeded SplitMix64 value type, injected rather than
  drawn from a shared generator, so `GetRandomPercent` is reproducible per session
  and per test without a lock.

`ConditionContext` is a value type and cheap to build, which is what lets a caller
running off the main actor compose one from a `WorldStateSnapshot`-derived
`GlobalResolution` instead of reaching into the `@MainActor` store. That is the same
discipline the snapshot itself follows.

Two properties of the evaluator matter to everything above it. First, no operation
throws: a condition OpenSky cannot answer evaluates to false carrying a
`ConditionFailure` that names the reason, which matches the store's own failure
model — this is runtime state, not file parsing, and there is no malformed input to
reject. Second, `ConditionTally` is a first-class result rather than a debug aid. It
mirrors `AS2Tally` from the [ActionScript 2 runtime](/engine/as2-runtime.md): capped
name tables with uncapped totals, one bucket per failure reason, and ranked
accessors. It is how the project measures which condition functions it still owes
the game, and it is what the vanilla coverage sweep reports; the numbers live on the
[conditions](/formats/conditions.md) page.

### First consumer: climate weather chances

`WeatherSelection.climateCandidates(worldspace:store:globals:)` honours the CLMT `WLST`
global beside each weather chance, so mutating that global visibly shifts which weather the
deterministic pick returns. The semantics chosen and why they are a choice are documented in
[weather runtime](/engine/weather.md). The resolver is passed in rather than stored, so
`WeatherStore` stays immutable; `WeatherSystem.setGlobalResolution(_:)` adopts a fresh
resolution and rerolls, and `GameViewController` hands it one on every `onGlobalMutation`.

The sidebar surface for globals exists: the Globals section under `World > Runtime State`
looks a GLOB up by editor ID and states its plugin default, its current resolved value, and
whether an override is in force as three separate facts. It is described with the rest of the
M10.2 panel work below.

### Global-variable tests

* `GlobalRecordTests` — all three FNAM types, the constant header flag, fractional values
  rounding onto integer types, and the malformed cases (wrong record type, wrong-size FNAM
  and FLTV, unknown type character, a record with no fields at all).
* `GlobalStoreTests` — FormID, editor-ID and case-insensitive lookup, session-stable key
  resolution, and the resolution seam: plugin default, runtime override, CTDA comparison
  values including one decoded from real CTDA bytes, and construction from a snapshot.
* `WorldStateGlobalsTests` — typed mutation and its rounding, no-op writes, reset and
  reset-all, journal contents and the sequence shared with the component log, the bounded
  window, the callback split, snapshot ordering and equality, and restore.
* `OpenSkySaveGlobalsTests` — the `GVAR` round trip, byte determinism across write orders,
  restore into a fresh store, an absent chunk, and the rejected payloads.
* `WeatherGlobalChanceTests` — the first consumer, listed in
  [weather runtime](/engine/weather.md).

## Applying state during a cell build

Issue #160 (item 10.1.3) is where the store stops being a ledger nobody reads. A build takes
a `WorldStateSnapshot` as a parameter — `CellSceneBuilder.buildScene(worldspaceEditorID:
gridX:gridY:state:)` and `buildInteriorScene(cellFormID:state:)`, both defaulting to
`.empty` — and the streaming seam carries it across the queue boundary:
`CellSceneProvider.buildCell(at:state:)` and `CellBuildRunning.enqueue(_:state:)`. The value
is captured on the main thread and is immutable, which is the whole reason the store itself
never leaves the main actor.

Application happens at exactly one point per build, in
`opensky/World/CellSceneBuilderRuntimeState.swift`. References are collected and given their
`ReferenceKey`s, then `effectiveReferences(refs:collected:state:counts:)` resolves each one
through `ReferenceState.applying(_:)` and returns two things: the index entries, which keep
every reference the plugin placed, and the *effective* references, which are what actually
gets placed. Render instancing and collision assembly both read that one effective array, so
a reference moved by a `ReferenceTransformOverride` cannot end up drawn in one place and
solid in another. Doors and interaction metadata read it too, so a disabled door is not
activatable.

* A reference whose resolved state is not visible (`isVisible == false` — disabled or
  deleted at runtime) is dropped and counted, exactly as an initially-disabled record is.
  The counts land in `BuildCounts.runtimeDisabled` / `runtimeDeleted`, fold into
  `CellLoadSummary.skippedRefCount`, and name themselves in the summary line as
  `runtime-disabled` and `runtime-deleted` ([cell scene build](/engine/cell-scene.md)).
* A reference carrying a transform override is placed at the override's position, rotation
  and scale instead of the record's DATA and XSCL values.
* Placed actors run the same visibility check. Their skips share the existing
  `disabledSkips` bucket so the 5.5 exact-accounting rule keeps holding; the per-actor log
  line says whether the record flag, a runtime disable, or a runtime delete applied. Because
  the record flag and the runtime component resolve through one `ReferenceState`, enabling a
  hidden actor at runtime makes it appear.
* The index keeps hidden references. An object a script disabled still exists, so it stays
  addressable through `CellScene.references` even though nothing drew it.

Deltas are looked up through `WorldStateSnapshot.deltasByKey()`, materialized once per
build. `subscript(key:)` is a linear scan, which is right for a single probe and wrong for a
loop over every reference in a cell.

Each snapshot also carries `sequence`, the store's journal sequence at capture time, and
each built `CellScene` records it as `stateSequence`. Comparing that against the store's
current sequence is how a later stage tells a scene built from stale state from a current
one. `sequence` is deliberately outside `WorldStateSnapshot`'s equality: it says when a
snapshot was taken, not what state it describes.

## Making a mutation visible: snapshot capture and cell rebuilds

Applying a snapshot during a build only helps if builds see the current store and if a
change to an already-drawn cell reaches the screen. Both are `CellStreamer`'s job, and the
logic lives in `opensky/World/CellStreamerRuntimeState.swift`.

`GameViewController` owns the session's `WorldStateStore` and wires it in
`wireStreaming(provider:renderer:)`: `CellStreamer.stateSource` is set to a closure that
snapshots the store, and `WorldStateStore.onMutation` is set to call
`CellStreamer.noteStateMutation(in:sequence:)`. Both run on the main thread, which is the
whole point — the store never leaves the main actor, and the snapshot is taken at dispatch,
the last main-thread moment before the build crosses to the serial runner.

The scheduling rule is one comparison. A mutation raises `cellMutationSequence` for the cell
the store attributed it to; a scene records the snapshot sequence it was built from as
`CellScene.stateSequence`; a resident scene is current exactly while `stateSequence` is at
least the recorded mutation sequence. A mutation for a resident cell queues a rebuild, and
`CellStreamCore.beginRebuild(_:)` moves the coordinate into a `rebuilding` set while keeping
it resident, so the old scene keeps rendering and its completion is integrated rather than
discarded as stale. Rebuild requests sit in their own queue behind first loads, so a cell
that has never been drawn still arrives center-out.

That single comparison also settles the race where a mutation lands while a build for the
same cell is already running. The in-flight result is always integrated, so the cell is
drawable as early as it can be; if it turns out to predate the mutation, a rebuild is queued
against a fresh snapshot at integration time. This is also what works around
`SerialCellBuildRunner.enqueue` deduplicating a coordinate that is still pending: the
rebuild request waits streamer-side and is dispatched after the stale completion drains,
rather than being silently dropped by the runner. Because a rebuild reconstructs the whole
cell from plugin bytes plus the current snapshot, applying it twice is indistinguishable
from applying it once — there is no delta to double-apply and none to lose.

Three consequences follow from state living only in the store:

* Unloading a cell changes nothing about state, and a pending rebuild for an unloaded cell
  is simply dropped (`pruneRebuildState()`). A returning cell rebuilds from plugin bytes
  plus the current snapshot, which reapplies the delta on its own.
* A mutation the store could not attribute to any cell rebuilds every resident cell. That is
  correctness first: the streamer has no cheaper way to tell which cell a reference lives
  in. Narrowing it means attributing the write, not guessing here.
* An interior owning the view has no provider entry point that builds it on its own — an
  interior only ever arrives as a door destination — so its rebuild re-runs the same door
  transition against a fresh snapshot, passing no camera so the swap leaves the player where
  they are standing instead of teleporting them back to the door.

Rebuilding the whole cell is the v1 answer; there is no per-instance patching, and the
per-frame budget is unchanged at one integration and one dispatch.

## Save and load: the snapshot through `OpenSkySaveStore`

Issue #161 (item 10.1.4) closes the loop: the store's own `snapshot()` is exactly the value
a save needs to write, and `restore(from:)` is exactly the operation loading a save
performs. Neither the store nor `WorldStateSnapshot` knows the byte layout that carries a
snapshot to disk — that is `OpenSkySaveStore`'s job, documented in full in
[OpenSky native save container](/formats/opensky-save.md). This section covers only the
seam between the two.

`OpenSkySaveStore` (`opensky/Formats/Save/OpenSkySaveStore.swift`) is a slot façade over the
`.osav` codec: `save(snapshot:fingerprint:metadata:toSlot:)` encodes a `WorldStateSnapshot`
plus a load-order fingerprint and writes it atomically to `<slot>.osav`;
`load(slot:verifyingAgainst:)` decodes a slot and, when a fingerprint is supplied, checks it
against the one recorded in the file; `listSlots()` enumerates what is on disk; slot names
are validated against a fixed character set before either becomes a filesystem path.
`OpenSkySaveStore.fingerprint(forRoot:)` and `fingerprint(forPlugins:)` build the load-order
fingerprint from a `GameDataRoot`, reading only each plugin's TES4 `HEDR` field.

Saving: `RuntimeStateControlProviding.save(toSlot:)` (`opensky/RuntimeStateControlProviding.swift`)
takes the live store's `snapshot()`, builds a fingerprint over the session's plugin load
order, and calls `OpenSkySaveStore.save`. Loading is the inverse and one step longer: the
store decodes the slot, optionally verifies the fingerprint, and calls
`WorldStateStore.restore(from:)` with the decoded snapshot. `restore(from:)` replaces every
delta, adopts the allocator position from `nextGeneratedSequence` so newly generated keys
never collide with ones already in the save, journals nothing (a load is not a sequence of
individually meaningful mutations), and fires one unattributed `onMutation` so every
resident cell rebuilds against the restored state — the same rebuild path described above
for a live mutation, just triggered once for the whole world instead of per reference.

Global overrides travel the same path. `snapshot()` carries them in `globals`, ordered by
`ReferenceKey` and part of snapshot equality; the encoder writes them into the additive
`GVAR` chunk; `restore(from:)` replaces the store's global map alongside its deltas and
fires one `onGlobalMutation` so the weather runtime and any other consumer adopt the
restored values.

Papyrus script state travels beside them, in the additive `PSCR` chunk, and is deliberately
the last thing `loadWorldState(slot:)` restores — after the snapshot and after the game
clock. The unattributed `onMutation` that `restore(from:)` fires only *queues* a rebuild for
each resident cell; those rebuilds re-attach their scripts on a later streaming update and
consult the [VM's](/engine/papyrus-vm.md) `firedOnInit` set to decide whether to enqueue
`OnInit`. Restoring that set after the fan-out is queued, but before any rebuild attach can
read it, is what stops every script re-running its `OnInit` on load.

A round trip is therefore: `WorldStateStore.snapshot()` -> `OpenSkySaveStore.save` -> bytes
on disk -> `OpenSkySaveStore.load` -> `WorldStateStore.restore(from:)` -> the same deltas,
in a possibly different store instance, driving the same resident cells to rebuild. The
save format's determinism guarantee (same `docs/formats/opensky-save.md` document) is what
lets a test compare the restored store's `snapshot()` against the original by equality
rather than by re-deriving the effect on a rendered cell.

## Verification — `World > Runtime State` and the M10.1 acceptance record

Issue #162 (item 10.1.5) is the milestone acceptance surface for everything above. The
`World > Runtime State` destination (`opensky/RuntimeStatePanelViewController.swift`,
sidebar id `runtimeState`, symbol `clock.arrow.circlepath`) is a normal sectioned panel whose
sections are each a `PanelSectionViewController` in
`opensky/Shell/Sections/RuntimeState*.swift`. M10.1 landed these four:

* **Inspect** (`PanelSection-runtimeStateInspect`) — read-only live counts: resident
  reference count, dirty count, allocator position, dropped journal entries, and the tail
  of the change journal. Readouts `RuntimeStateStatsLabel`, `RuntimeStateJournalStatsLabel`.
* **Change** (`PanelSection-runtimeStateChange`) — the one target field
  (`RuntimeStateTargetControl`, a typed FormID or the current interaction target) plus
  Disable/Enable/Nudge actions (`RuntimeStateDisableControl`, `RuntimeStateEnableControl`,
  `RuntimeStateNudgeControl`). Readout `RuntimeStateChangeStatsLabel`.
* **Reset** (`PanelSection-runtimeStateReset`) — reset the Change section's target
  (`RuntimeStateResetTargetControl`) or every reference at once
  (`RuntimeStateResetAllControl`). Readout `RuntimeStateResetStatsLabel`.
* **Save** (`PanelSection-runtimeStateSave`) — a slot name field
  (`RuntimeStateSlotControl`) plus Save/Load actions (`RuntimeStateSaveControl`,
  `RuntimeStateLoadControl`), reporting the slots on disk and the outcome of the last
  operation, including a failed load's typed error message verbatim. Readout
  `RuntimeStateSaveStatsLabel`.

`GameViewControllerRuntimeState.swift` bridges `RuntimeStateControlProviding` onto
`GameViewController`: the current interaction target resolves through the streamer's
resident reference index, typed FormIDs are parsed as hex, and save metadata takes its app
version from `CFBundleShortVersionString`. The destination is overridden whenever
`dirtyReferenceCount > 0`, and Reset all calls `resetAllReferenceState()`.

`M10StateAcceptanceTests.swift` drives the panel half of the gate end to end on one
provider set — select the destination, inspect the live snapshot, disable and nudge a
reference by typed FormID, save a slot, load it back, and reset everything — reading every
readout back by accessibility identifier out of the built view hierarchy.
`M10StateAcceptanceEngineTests.swift` proves the engine half with no fakes: a real
`WorldStateStore`, a real `CellStreamer`, and a real `OpenSkySaveStore` show that mutating
two references in a resident cell, evicting and reloading that cell by walking away and
back, saving to a slot, and restoring into a brand-new store produces an identical
`WorldStateSnapshot`, allocator position included, and that a `CellSceneBuilder` fed the
restored snapshot drops the disabled reference and moves the nudged one exactly as the
original build did. `M10StateAcceptanceRealDataTests.swift` (env-gated, `make realtest`) ran
green against the real install: a ten-plugin load order fingerprinted with `skyrim.esm`
first, a four-delta snapshot round-tripped through a real slot file and verified against
that fingerprint, and a changed load order refused on load.

```text
Milestone: M10.1.5
Sidebar path: World > Runtime State
Destination id: Destination-runtimeState
Controls exercised: RuntimeStateTargetControl, RuntimeStateDisableControl, RuntimeStateEnableControl, RuntimeStateNudgeControl, RuntimeStateResetTargetControl, RuntimeStateResetAllControl, RuntimeStateSlotControl, RuntimeStateSaveControl, RuntimeStateLoadControl
Readout: RuntimeStateStatsLabel, RuntimeStateJournalStatsLabel, RuntimeStateChangeStatsLabel, RuntimeStateResetStatsLabel, RuntimeStateSaveStatsLabel
Deterministic tests: M10StateAcceptanceTests, RuntimeStatePanelTests, DestinationRegistryTests
Local A/B (optional, never committed): none
```

## Verification — the M10.2 panel surfaces and the M10 acceptance record

Issue #166 (item 10.2.5) closes the milestone by extending the same destination rather than
adding new ones. Time, globals and conditions all inspect and mutate the same runtime world
state, which is the thing this destination is named for, so they became three more sections
under it. Section order follows the order a session reaches for them: read the store, then
time, then globals, then conditions (which read both), then the three change-and-restore
surfaces that were already there.

* **Time** (`PanelSection-runtimeStateTime`) — an hour slider (`RuntimeStateHourControl`),
  a day field, month pop-up and year field applied together
  (`RuntimeStateDayControl`, `RuntimeStateMonthControl`, `RuntimeStateYearControl`,
  `RuntimeStateApplyDateControl`), and the timescale
  (`RuntimeStateTimescaleControl`, `RuntimeStateApplyTimescaleControl`). Readout
  `RuntimeStateTimeStatsLabel` prints the time, the date, days passed, the timescale, and
  whether the world simulation is paused.
* **Globals** (`PanelSection-runtimeStateGlobals`) — an editor-ID combo box completing over
  every loaded GLOB (`RuntimeStateGlobalControl`), a value field
  (`RuntimeStateGlobalValueControl`), and Set and Reset actions
  (`RuntimeStateGlobalApplyControl`, `RuntimeStateGlobalResetControl`). Readout
  `RuntimeStateGlobalsStatsLabel`.
* **Conditions** (`PanelSection-runtimeStateConditions`) — a source combo box over the
  condition lists the session can evaluate (`RuntimeStateConditionSourceControl`, today the
  music tracks carrying CTDA conditions, the only decoded consumer in the engine) and an
  Evaluate action (`RuntimeStateConditionEvaluateControl`). Two readouts:
  `RuntimeStateConditionStatsLabel` for the verdict and the per-condition reasons, and
  `RuntimeStateConditionTallyStatsLabel` for the session's running `ConditionTally`.

Four decisions in that surface are worth stating, because each one had an obvious wrong
answer.

Pause is a readout, not a checkbox. `Renderer.worldSimPaused` is owned by
`MenuModeController` ([menu mode](/engine/menu-mode.md)), so a panel toggle would be silently
overwritten the next time the menu opened or closed. `World > System Menu` keeps the toggle;
the Time section only reports what it did, because a clock that appears stuck is otherwise
inexplicable.

Timescale is not a clock property. It is the `TimeScale` GLOB, written through
`WorldStateStore.setGlobal`, which is why it is the timescale — and not elapsed time — that
makes the Time section overridden: a clock that has advanced is a world that has been played,
not a knob left in a non-default position. The five projected time globals (`GameHour`,
`GameDaysPassed`, `GameDay`, `GameMonth`, `GameYear`) store no override at all, so scrubbing
the clock does not reroll weather on every tick.

The journal tail is one log, not three. `GameViewController.runtimeStateJournalTail()`
interleaves the component ring and the globals ring by their shared monotonic `sequence`,
which reproduces the exact causal order the session performed the writes in. Both rings are
already oldest-first, so the newest eight overall can only come from the newest eight of
each, and the suffixes are taken before the sort rather than walking a full 4096-entry window
on a 2 Hz readout. Clock scrubs appear there too: a `GameHour` write journals on the globals
ring even though it moves the clock instead of storing an override.

Per-condition reasons come from the single-condition entry point.
`ConditionEvaluator.evaluate(_ list:)` returns one verdict and a flattened `failures` array,
which cannot say which condition produced which failure, so
`RuntimeStateConditionRunner.report(source:conditions:context:tally:)`
(`opensky/RuntimeStateConditionRunner.swift`) evaluates each condition once and recombines
the booleans in `RuntimeStateConditionRunner.combine(conditions:outcomes:)` with the same OR
grouping the evaluator applies. Evaluating both ways instead would count every condition
twice in the tally and draw twice from the `ConditionRandom` stream, so `GetRandomPercent`
would disagree with itself between the verdict and the reasons. `combine` is pinned against
`ConditionEvaluator.evaluate(_ conditions:)` across all eight truth-table shapes.

Overridden-ness for the destination is the union of the three surfaces that can sit away from
plugin data: dirty references, overridden globals, and a non-default timescale.
`RuntimeStateResetSection.resetToDefaults(provider:)` clears all three, which is what the
sidebar's Reset control and the View menu's Reset all run.

`M10AcceptanceTests` drives the whole milestone on one provider set through the real sidebar
and registry-built panels, reading every readout back by accessibility identifier: mutate a
reference, mutate a global, scrub the clock, save a slot, load it into a fresh instance, and
compare. `M10AcceptanceEngineTests` proves the same round trip with no fakes and asserts the
journal-independent snapshot equality the gate names — `WorldStateSnapshot.==` deliberately
excludes `sequence`, so the saved store's snapshot (`sequence == 6`) compares equal to the
restored one (`sequence == 1`). The `CLOK` and `GVAR` chunks that carry the clock and the
globals were additive and deliberately did not bump `OpenSkySaveFormat.currentVersion`: an
older build skips an unknown chunk by its declared length and loads the rest
([OpenSky native save container](/formats/opensky-save.md)).

`M10AcceptanceWeatherTests` pins weather and time staying synchronized. With `TimeScale` at
3600 — one game hour per real second — ninety steps of 0.5 real seconds elapse 45 game hours,
starting at 08:00 on the vanilla start date and ending at 05:00 on 19 Last Seed 4E 201.
`WeatherSystem.rerollGameHours` is 6, so seven reroll boundaries fall inside the run and no
observed weather change may land off a 6-hour boundary. `M10AcceptanceRealDataTests`
(env-gated on `OPENSKY_DATA_ROOT`, run with `make realtest`) repeats it against the retail
install: 664 GLOB records decoded from `Skyrim.esm`, `TimeScale` at its plugin default of 20
with a session override of 3600, Tamriel offering a pool of 84 selectable weathers, 45.0 game
hours elapsed, an end state of `05:00 19 Last Seed, 4E 201` with the `GameHour` projection
reading 5.0, and the observed weather change landing at exactly game hour 6.0.

One subtlety is worth recording, because it cost a false-positive test. On real data "the
weather changed" is not by itself proof that a reroll fired: Tamriel's authored chances are
lopsided enough that every automatic pick across the run can legitimately return the same
weather, and a reroll that reselects the showing weather is by design a no-op. The real-data
test therefore forces a contrasting weather, resumes automatic selection with the counter at
zero, and asserts the cadence structurally rather than inferring it from a visible change.

```text
Milestone: M10.2.5
Sidebar path: World > Runtime State
Destination id: Destination-runtimeState
Controls exercised: RuntimeStateTargetControl, RuntimeStateDisableControl, RuntimeStateEnableControl, RuntimeStateNudgeControl, RuntimeStateResetTargetControl, RuntimeStateResetAllControl, RuntimeStateSlotControl, RuntimeStateSaveControl, RuntimeStateLoadControl, RuntimeStateHourControl, RuntimeStateDayControl, RuntimeStateMonthControl, RuntimeStateYearControl, RuntimeStateApplyDateControl, RuntimeStateTimescaleControl, RuntimeStateApplyTimescaleControl, RuntimeStateGlobalControl, RuntimeStateGlobalValueControl, RuntimeStateGlobalApplyControl, RuntimeStateGlobalResetControl, RuntimeStateConditionSourceControl, RuntimeStateConditionEvaluateControl, plus TimeOfDayControl on World > Environment > Weather
Readout: RuntimeStateStatsLabel, RuntimeStateJournalStatsLabel, RuntimeStateChangeStatsLabel, RuntimeStateResetStatsLabel, RuntimeStateSaveStatsLabel, RuntimeStateTimeStatsLabel, RuntimeStateGlobalsStatsLabel, RuntimeStateConditionStatsLabel, RuntimeStateConditionTallyStatsLabel, TimeOfDayStatsLabel
Deterministic tests: M10AcceptanceTests, M10StateAcceptanceTests, RuntimeStatePanelTests, RuntimeStatePanelTimeTests, RuntimeStatePanelGlobalsTests, RuntimeStatePanelConditionsTests, RuntimeStateConditionRunnerTests, GameViewControllerRuntimeStateJournalTests, DestinationRegistryTests, DestinationRegistryRuntimeStateTests
Local A/B (optional, never committed): none
```

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
* [Record decoders](/formats/records.md) — the GLOB layout behind `GlobalStore`, and
  [conditions](/formats/conditions.md) — the CTDA comparison operand the lookup seam
  resolves.
* [Weather runtime](/engine/weather.md) — the first consumer of resolved global values, and
  the chosen CLMT WLST semantics.
* [OpenSky native save container](/formats/opensky-save.md) — the `.osav` byte layout that
  `OpenSkySaveStore` writes and reads on behalf of the save/load section above.
* [Main-app UI framework + placement](/tools/app-ui.md) and
  [Sidebar verification convention](/tools/sidebar-acceptance.md) — how `World > Runtime
  State` was registered and what its acceptance record must contain.

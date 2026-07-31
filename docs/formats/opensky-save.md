---
type: File Format
title: OpenSky native save container (.osav)
description: Byte layout of OpenSky's own .osav save file, its determinism and version rules.
tags: [format, save, io, world-state, determinism]
timestamp: 2026-07-31T00:00:00Z
---

# OpenSky native save container

`.osav` is the file OpenSky writes when it saves a session. It carries the
[world-state snapshot](/engine/runtime-state.md) — every runtime deviation from what the
plugins say — plus the load order the session was running, and enough header metadata to
describe the file to a user before anything is restored.

This format is OpenSky's own. It is not Bethesda's `.ess`, it is not derived from `.ess`,
and nothing in it is reverse engineered, so this document is the specification rather than
a description of someone else's. There is no external reference to cite. OpenSky never
writes a Bethesda save file; read-only import of an existing `.ess` is a separate,
far-future item and shares none of the layout below.

Implementation: `opensky/Formats/Save/`. All integers are little-endian, floats are IEEE
754 single precision written as their little-endian bit pattern, and strings are a `UInt16`
byte length followed by that many UTF-8 bytes. The file extension is `osav`.

## Contents

* Design goals
* Header — the non-deterministic region
* The deterministic region
* Load-order fingerprint
* Chunks
* `RDLT` entry layout
* Version policy
* Defensive decoding
* Where saves live and how they are written
* The slot store — `OpenSkySaveStore`
* Future options
* Verification

## Design goals

Three properties drove every choice in the layout.

Deterministic bytes. Everything after the header metadata is a pure function of the
`WorldStateSnapshot` and the load-order fingerprint. Two sessions that reached the same end
state through different mutation orders write byte-identical tails, which makes a
round-trip test an exact byte comparison rather than a structural one and makes a
corruption report reproducible.

Forward and backward tolerance, applied asymmetrically. The body is a stream of tagged,
length-prefixed chunks, so a build that does not recognise a chunk skips it and still loads
everything else. Component kinds inside a chunk get the opposite treatment: an unrecognised
one is an error, because a delta that silently lost components produces a world that is
quietly wrong rather than one that is merely missing a feature.

Defensive decoding. Every declared count is checked against the bytes that actually remain
before any storage is reserved for it, so a corrupt four-byte length is a thrown error
instead of a multi-gigabyte allocation.

## Header — the non-deterministic region

| offset | type   | field          | notes                                     |
| ------ | ------ | -------------- | ----------------------------------------- |
| 0x00   | char4  | magic          | ASCII `OSAV`                              |
| 0x04   | uint32 | formatVersion  | 1 — the only version this build reads     |
| 0x08   | uint32 | metadataLength | byte length of the metadata block below   |
| 0x0C   | bytes  | metadata       | `metadataLength` bytes                    |

The metadata block holds, in order:

| type   | field             | notes                                          |
| ------ | ----------------- | ---------------------------------------------- |
| uint64 | creationTimestamp | seconds since the unix epoch                    |
| string | appVersion        | uint16 byte length plus UTF-8 build version     |

The timestamp is injected by the caller rather than read from the clock inside the encoder.
Determinism tests must be able to produce the same bytes twice, and a save that is replayed
or migrated should keep its original creation time rather than acquiring a new one.

The block is length-delimited, and the decoder stops reading after `appVersion` no matter
how many bytes are left inside it. Trailing bytes a newer build added are skipped rather
than mistaken for the start of the fingerprint, so metadata can grow without a
`formatVersion` bump.

## The deterministic region

Everything after the metadata bytes — the fingerprint and every chunk — is the deterministic
region. Three rules produce that guarantee:

* Entries come out of `WorldStateSnapshot` in its canonical `ReferenceKey` order, which the
  store establishes by sorting its dirty keys, not by mutation order.
* Components within an entry are written in ascending on-disk tag order, and the decoder
  rejects any other order, so a given delta has exactly one legal spelling.
* Nothing in the encoder consults the clock, a hash seed, or dictionary iteration order.

Only the header depends on `SaveCreationMetadata`, so two saves of the same world state
taken at different times differ only in their first few dozen bytes.

## Load-order fingerprint

The fingerprint records the plugins the session was running, in load order.

| type   | field       | notes                                             |
| ------ | ----------- | ------------------------------------------------- |
| uint32 | pluginCount | number of entries that follow                     |

Then `pluginCount` entries of:

| type   | field        | notes                                                  |
| ------ | ------------ | ------------------------------------------------------ |
| string | name         | plugin file name, spelled as it appears on disk        |
| uint32 | hedrVersion  | bit pattern of the HEDR version `Float` (0.94/1.7/1.71) |
| uint32 | recordCount  | bit pattern of the HEDR record and group count `Int32`  |
| uint32 | nextObjectID | HEDR next object ID                                    |

The three statistics come straight from the plugin's TES4 HEDR field (see
[FormID and TES4 header](/formats/formid.md)). The Creation Kit rewrites them whenever the
file changes, so together they are a cheap "is this the same plugin as before" check that
costs nothing compared with hashing whole archives.

`OpenSkySaveFile.verifyFingerprint(against:)` compares the saved list against the installed
one position by position and throws `fingerprintMismatch` naming the first difference.
File-name case is ignored, matching how plugin names are compared everywhere else in the
engine — `ReferenceKey` already normalises to lowercase. Order matters and a reordered load
order is a mismatch rather than an accepted file: plugin-defined `ReferenceKey`s are
name-based and survive reordering, but records, masters, and object IDs do not.

Verification is deliberately not part of decoding. Decoding needs nothing but the file, so
an inspector, a test, or a repair tool can read a save on a machine with no game install at
all, and the app can show what a save contains before explaining why it cannot be loaded.

A real `plugins.txt` load order does not exist in the engine yet. The fingerprint is
list-shaped now so that it is already the right shape when it does.

## Chunks

The rest of the file is a sequence of chunks, repeating until end of file.

| type   | field         | notes                                       |
| ------ | ------------- | ------------------------------------------- |
| char4  | tag           | four ASCII bytes                            |
| uint32 | payloadLength | byte length of the payload that follows     |
| bytes  | payload       | `payloadLength` bytes                       |

A chunk whose declared length runs past the end of the file is
`chunkBoundsViolation(tag:)`. A chunk whose tag this build does not know is skipped using
that declared length, which is what makes a newer build's save loadable in an older one.

Version 1 defines two chunks; `GVAR`, `CLOK`, `PSCR` and `PTMR` were added additively
afterwards.

`GALC` — generated-reference allocator position. The payload must be exactly eight bytes;
any other size is `invalidValue`.

| type   | field                 | notes                                              |
| ------ | --------------------- | -------------------------------------------------- |
| uint64 | nextGeneratedSequence | restores `GeneratedReferenceAllocator`              |

A restored session resumes handing out generated keys from this position, so a new key
cannot collide with one already in the save. A file with no `GALC` chunk restores an
allocator that has handed out nothing, which is sequence 1.

`RDLT` — runtime reference deltas, one entry per dirty reference.

| type   | field      | notes                                     |
| ------ | ---------- | ----------------------------------------- |
| uint32 | entryCount | number of entries that follow             |
| bytes  | entries    | `entryCount` entries, layout below        |

`GVAR` — runtime global-variable overrides, one entry per overridden global. Added by
issue #165 after version 1 shipped, and deliberately **without** bumping `currentVersion`: a new
chunk is exactly what the tag-and-length stream is tolerant of, so a build that predates it
skips the chunk by its declared length and loads the rest of the save. The reverse direction
is equally safe, because a file with no `GVAR` chunk means no global was overridden.

| type   | field      | notes                                     |
| ------ | ---------- | ----------------------------------------- |
| uint32 | entryCount | number of entries that follow             |
| bytes  | entries    | `entryCount` entries, layout below        |

Each entry is a reference key (the same tagged encoding `RDLT` uses, here naming the GLOB
record rather than a placed object), then:

| type   | field     | notes                                                    |
| ------ | --------- | -------------------------------------------------------- |
| uint8  | valueType | declared FNAM type: 0 short, 1 long, 2 float              |
| float32| value     | the current value, already coerced onto `valueType`       |

Entries are written in `ReferenceKey` total order, so the chunk is deterministic on the same
terms as `RDLT`. An unknown `valueType` tag is `invalidValue`: unlike an unknown chunk, a
value whose type is unreadable cannot be skipped without silently changing what the global
means. The declared type is stored rather than re-derived from the plugin so a save stays
readable without the game data it was written against.

`CLOK` — game clock state (issue #164), added additively like `GVAR` and equally without a
`currentVersion` bump. The payload must be exactly eight bytes; any other size is
`invalidValue`.

| type    | field            | notes                                                   |
| ------- | ---------------- | ------------------------------------------------------- |
| float64 | totalGameSeconds | `GameClock.totalGameSeconds`, IEEE 754 bit pattern      |

The clock's whole state is this one number — game seconds since the calendar epoch (see
[game clock](/engine/game-clock.md)) — so nothing else needs encoding. A non-finite or
negative value is `invalidValue` rather than a clock. A file with no `CLOK` chunk — every
pre-clock save — restores the vanilla-start clock, and an encoder given no clock writes no
chunk, keeping pre-clock byte-equality tests valid.

`PSCR` — Papyrus script instance state (issue #171), one entry per live script instance.
Additive like `GVAR` and `CLOK`, and equally without a `currentVersion` bump. Script state
is a new chunk rather than a new component kind inside `RDLT` for exactly the reason the
[version policy](#version-policy) gives: a component kind is versioned by `formatVersion`,
so putting it there would force every older build to refuse the whole file. A session with
no instances writes no chunk at all, so a build or a session without a VM produces the same
bytes it always did.

| type   | field         | notes                                     |
| ------ | ------------- | ----------------------------------------- |
| uint32 | instanceCount | number of instances that follow           |
| bytes  | instances     | `instanceCount` instances, layout below   |

Each instance is a reference key — the same tagged encoding `RDLT` uses, here naming the
reference the script is attached to — then:

| type   | field         | notes                                                        |
| ------ | ------------- | ------------------------------------------------------------ |
| string | scriptName    | lowercased script name                                        |
| string | activeState   | the instance's active state, spelled as the script spelled it |
| uint8  | firedOnInit   | exactly 0 or 1; whether `OnInit` has already been delivered   |
| uint32 | variableCount | variables that follow                                         |

Each variable:

| type   | field           | notes                                              |
| ------ | --------------- | -------------------------------------------------- |
| string | declaringScript | lowercased name of the script that declared it     |
| string | name            | lowercased variable name                            |
| uint8  | valueTag        | which of the five persistable value kinds follows   |
| bytes  | value           | the tag's payload, below                            |

| tag  | kind    | payload                                                       |
| ---- | ------- | ------------------------------------------------------------- |
| 0    | none    | nothing                                                       |
| 1    | boolean | one byte, exactly 0 or 1                                      |
| 2    | integer | uint32, the bit pattern of the `Int32`                        |
| 3    | float   | uint32, the IEEE 754 binary32 bit pattern                     |
| 4    | string  | uint16 byte length plus UTF-8 bytes                           |

A `PapyrusValue` may also be an object handle or an array. Neither has a tag, because
neither is persistable: their identity is allocated by the running VM and means nothing
after a reload. The encoder writes both with the `none` tag, which is also what the
[Papyrus virtual machine](/engine/papyrus-vm.md) already snapshots them as, so a restored
script sees its compiled default rather than a handle pointing at nothing.

Entries come out of `PapyrusWorldRuntime.instanceStates()` sorted by `PapyrusInstanceKey`,
with each instance's variables sorted by `(declaringScript, name)`, so the chunk is
deterministic on the same terms as `RDLT` and re-encoding an unchanged runtime produces
identical bytes. Both declared counts are validated before anything reserves storage, using
`minimumScriptEntrySize` (16 bytes: an empty plugin key, an empty script name, an empty
state name, the flag and the variable count) and `minimumScriptVariableSize` (5 bytes: two
empty names and a `none` tag).

The snapshot's journal `sequence` is not saved. It is session-local bookkeeping, and a
decoded snapshot always reports sequence 0.

`PTMR` — pending Papyrus update-timer slots (issue #277), one entry per armed slot of a
persistent script instance. Additive like `GVAR`, `CLOK` and `PSCR`, and equally without a
`currentVersion` bump: an older build skips the chunk by its declared length and loads the
rest of the save, restoring a world where no script has a pending `OnUpdate` or
`OnUpdateGameTime`. Like `PSCR`, a session that armed no timer writes no chunk at all, so
its bytes are identical to a build that predates this chunk.

| type   | field      | notes                                     |
| ------ | ---------- | ----------------------------------------- |
| uint32 | entryCount | number of entries that follow             |
| bytes  | entries    | `entryCount` entries, layout below        |

Each entry is a reference key — the same tagged encoding `RDLT` uses, here naming the
instance's reference — then:

| type   | field         | notes                                                              |
| ------ | ------------- | ------------------------------------------------------------------- |
| string | scriptName    | lowercased script name, completing the instance key                 |
| uint8  | slot          | which of the four timer slots this entry is, table below            |
| uint64 | interval      | the registered interval, an IEEE 754 binary64 bit pattern            |
| uint64 | remaining     | delay still to run, same unit and encoding as `interval`             |

`interval` and `remaining` are in the slot's own unit: real seconds for the two real-time
slots, game hours for the two game-time slots. `remaining` is a delay relative to the
moment the save was written, never an absolute deadline, so a restore re-anchors against
whatever clock state the load establishes and the wall or game time spent between save and
load never counts toward the timer.

| slot | value | meaning                          |
| ---- | ----- | --------------------------------- |
| 0    | 0     | real-time, repeating              |
| 1    | 1     | real-time, single-shot            |
| 2    | 2     | game-time, repeating              |
| 3    | 3     | game-time, single-shot            |

The slot byte is `PapyrusUpdateTimerSlot`'s own raw value, a number the
[Papyrus virtual machine](/engine/papyrus-vm.md#update-timers) already declares stable for
on-disk use, so no separate tag table can drift out of sync with it. A byte outside 0...3 is
`invalidValue`, the same treatment an unknown `PSCR` value tag gets: this is a shape the
decoder cannot interpret at all, not a value it can normalize.

Entries come out of `PapyrusWorldRuntime.timerStates()` sorted by instance key then slot,
so re-encoding an unchanged runtime produces identical bytes, on the same terms as `PSCR`
and `RDLT`. The declared count is validated before anything reserves storage, using
`minimumTimerEntrySize` (26 bytes: an empty plugin key, an empty script name, the slot
byte, and the two `Float64` bit patterns). The encoder never reads a clock; it only writes
whatever `remaining` the runtime's `timerStates()` computed.

## `RDLT` entry layout

Each entry is a reference key, a cell location, and a component list.

| type   | field          | notes                                             |
| ------ | -------------- | ------------------------------------------------- |
| key    | key            | the reference this delta applies to               |
| cell   | cell           | where the reference lived when it was dirtied     |
| uint8  | componentCount | components that follow                            |
| bytes  | components     | `componentCount` components in ascending tag order |

Reference key, used both here and for `lastActivator` inside an activation component:

| tag  | kind      | payload                                                     |
| ---- | --------- | ----------------------------------------------------------- |
| 0    | plugin    | string plugin name, then uint32 `objectID`                   |
| 1    | generated | uint64 allocator sequence                                    |

Cell location:

| tag  | kind     | payload                                                          |
| ---- | -------- | ---------------------------------------------------------------- |
| 0    | absent   | none                                                             |
| 1    | exterior | uint32 x and uint32 y, bit patterns of the `Int32` cell coordinates |
| 2    | interior | uint32 raw `FormID` of the cell                                  |

Components. Each is a `UInt8` tag followed by its payload, and tags must strictly ascend
within an entry. Strict ascent makes "at most one value per slot" checkable in a single
pass and keeps the encoder's output the only accepted spelling of a given delta.

| tag  | component   | payload                                                            |
| ---- | ----------- | ------------------------------------------------------------------ |
| 0    | enableState | one byte, exactly 0 or 1                                            |
| 1    | transform   | position x/y/z, rotation x/y/z, then scale — seven float32          |
| 2    | activation  | uint32 `activationCount`, `isOpen` byte, `hasLastActivator` byte,   |
|      |             | then a reference key when that byte is 1                            |
| 3    | deletion    | one byte, exactly 0 or 1                                            |

Tag values are written out case by case in the code rather than derived from the enum's
declaration order, because declaration order is a source-level detail that may change while
these byte values may not.

## Version policy

A new chunk tag is additive and needs no `formatVersion` bump. Unknown chunks are skipped by
their declared length, so an older build reading a newer save loses that chunk's feature and
nothing else.

A bump is required for a change to an existing chunk's payload layout, for a new component
kind, and for a changed component payload. Unknown component kinds are rejected rather than
skipped, so an older build cannot degrade gracefully through one; it would have to guess how
many bytes to step over, and guessing wrong desynchronises the rest of the entry stream.

The asymmetry is deliberate. A missing whole chunk is a degraded but honest world — the
build plainly does not have the feature. A delta that silently lost some of its components
is a world that looks correct and is not, which is the worse failure to ship.

`formatVersion` is checked for exact equality on load. A file declaring anything other than
the version this build implements fails with `unsupportedVersion(found:)` rather than being
parsed hopefully.

## Defensive decoding

All decoding goes through `SaveReader`, a bounds-checked cursor that converts every
underlying reader failure into `OpenSkySaveError.truncated(context:)` with the name of the
structure being read, so callers only ever switch over one error type.

* Every declared count is validated against the bytes actually remaining, divided by the
  smallest possible size of one element, before any array reserves capacity.
* A chunk payload is decoded through a fresh cursor over just that payload, so a corrupt
  count inside a chunk cannot walk into the next chunk's bytes.
* A string length past the end of the data is a truncation, never an allocation — the bytes
  are read before they are interpreted.
* A byte the format defines as boolean must be exactly 0 or 1. Treating `0x7F` as `true`
  would hide a writer or decoder bug behind a plausible-looking world.

One value is normalised rather than rejected, and the asymmetry is deliberate. A `PSCR`
float whose bit pattern is NaN or infinite decodes as `0.0` and the rest of the save loads.
Papyrus arithmetic can legitimately produce a non-finite number — a division by zero inside
a mod script is not corruption — and refusing a whole world over one drifted script variable
would be the worse failure. A non-finite `CLOK` value, by contrast, has no plausible
legitimate origin, so `decodeClock` still rejects it as `invalidValue`. An unknown `PSCR`
value tag is likewise a hard `invalidValue`: a shape this build cannot interpret at all
cannot be normalised into anything honest.

`PTMR`'s `interval` and `remaining` follow the same normalise-rather-than-reject rule,
widened slightly: non-finite **or negative** decodes as `0.0`, not only non-finite. A
timer duration has no legitimate negative value the way a script float might, and
`PapyrusUpdateTimerRegistry` itself clamps a non-finite or non-positive interval to zero
on registration, so a normalized `PTMR` entry decodes to exactly what the registry would
have produced from the same input and simply fires on the next fixed step. An unknown
`PTMR` slot byte is a hard `invalidValue`, for the same reason an unknown `PSCR` value tag
is: it is a shape this build cannot interpret, not a value to normalize.

The error cases, from `OpenSkySaveError.swift`:

| case                                              | meaning                                          |
| ------------------------------------------------- | ------------------------------------------------ |
| `badMagic`                                        | the first four bytes are not ASCII `OSAV`        |
| `unsupportedVersion(found:)`                      | the file declares a layout version this build does not implement |
| `truncated(context:)`                             | the file ends inside a structure that required more bytes; `context` names that structure |
| `invalidCount(chunk:count:remaining:)`            | a declared element count cannot fit in the bytes that remain |
| `invalidValue(context:)`                          | a value the format does not define — a non-boolean boolean byte, an unknown tag, or out-of-order component kinds |
| `chunkBoundsViolation(tag:)`                      | a chunk's declared payload length runs past the end of the file |
| `fingerprintMismatch(reason:)`                    | the save was written against a different load order than the one installed now |

Every case is `Equatable`, so a test can assert the exact failure a given corruption
produces rather than merely that something threw.

Encoding, by contrast, is total and does not throw: every input the engine can produce has a
byte representation. The one lossy edge is a string longer than 64 KiB, which is cut back to
the last whole UTF-8 scalar that fits. A plugin file name or build version that long is
already nonsense, and losing the save over it would be worse than losing the tail.

## Where saves live and how they are written

Saves go in the user's Application Support directory,
`~/Library/Application Support/OpenSky/Saves/`, created on demand. Never the repository, and
never the game install: the install is read-only external input, and a save is the user's
data rather than ours.

`OpenSkySaveIO.writeAtomically(_:to:)` writes in three steps, each of which is there for a
specific failure:

1. Write to a temp file created beside the destination, in the same directory. Beside,
   because a rename only replaces atomically within a single filesystem, and a temp file in
   `/tmp` may well be on another one.
2. `synchronize()` the handle before closing, forcing the contents to disk. Skipping this
   keeps the rename atomic but allows the directory metadata to land before the file
   contents after a power loss, which is the classic way to end up with a file full of
   zeroes.
3. `rename()` over the destination. A rename within one filesystem replaces the target in a
   single step, so a crash or a full disk mid-write leaves the previous save intact instead
   of a half-written one.

Any failure removes the temp file, so a failed save leaves neither a damaged destination nor
litter behind.

## The slot store — `OpenSkySaveStore`

Issue #161 (item 10.1.4) adds `OpenSkySaveStore` (`opensky/Formats/Save/OpenSkySaveStore.swift`),
a slot façade over the codec above so callers name a save by a short slot name rather than
building a `URL` themselves. It owns one directory — the Saves directory described above, or
an injected one for tests — and every operation resolves a slot name to `<slot>.osav` inside
it.

* `save(snapshot:fingerprint:metadata:clock:scripts:toSlot:)` encodes a
  `WorldStateSnapshot`, a load-order fingerprint, and `SaveCreationMetadata`, then writes the
  result through `OpenSkySaveIO.writeAtomically(_:to:)`. `clock` and `scripts` are defaulted,
  so a caller with neither writes neither chunk and produces the bytes it always did;
  `OpenSkySaveEncoder.encode` and `OpenSkySaveFile.init` carry the same defaults for the same
  reason.
* `load(slot:verifyingAgainst:)` reads `<slot>.osav` and decodes it; the fingerprint
  parameter is optional, so a caller can inspect a save with no install present at all, and
  when supplied it is checked with the same `verifyFingerprint(against:)` used everywhere
  else.
* `listSlots()` enumerates the directory and returns the slot names present, sorted.

Slot names are validated before they ever become a path component: empty, containing a path
separator, or containing any character outside a small allow-list is rejected as a typed
`OpenSkySaveStoreError` rather than passed to the filesystem, since a slot name ultimately
comes from a text field the user can type into
([the Save section of `World > Runtime State`](/engine/runtime-state.md)).
`OpenSkySaveStoreError.slotNotFound(_:)` is the other case, raised by `load` when the named
file does not exist.

`OpenSkySaveStore.fingerprint(forRoot:)` and `fingerprint(forPlugins:)` build the load-order
fingerprint from a live install: they resolve the plugin load order through
`PluginLoadOrder` and read each plugin's `PluginHeader.stats` (the same `HEDR` fields the
[load-order fingerprint](#load-order-fingerprint) section above lists), so a caller never
hand-assembles a `[SavePluginFingerprint]` from raw TES4 bytes itself.

## Future options

Compression is a deliberate non-feature for now. Saves at this stage hold deltas rather than
whole worlds, so they are small, and an uncompressed file is directly inspectable in a hex
editor when a determinism test disagrees with itself.

Global variables landed as the additive `GVAR` chunk (issue #165), the game clock as `CLOK`
(issue #164), Papyrus script state as `PSCR` (issue #171), and pending Papyrus update
timers as `PTMR` (issue #277). None of the four cost a `formatVersion` bump, exactly as the
version policy above predicts.

Read-only import of a Bethesda `.ess` save is a separate item and shares nothing with this
layout. OpenSky will never write one.

## Verification

Unit tests use synthetic in-code fixtures only; no game content is involved, and none is
needed, because the format is entirely our own. They cover round-trip equality, byte-level
determinism across differing mutation orders, unknown-chunk skipping, `GVAR` round trip and
its rejected payloads (`openskyTests/OpenSkySaveGlobalsTests.swift`), fingerprint
comparison including reordering and case, and one test per `OpenSkySaveError` case driven by
a targeted corruption.

`openskyTests/OpenSkySavePapyrusTests.swift` covers `PSCR` on the same terms: a script-state
round trip, byte-level determinism, an absent chunk meaning no script state, a truncated
entry, a bogus instance count, a bogus variable count, an unknown value tag, non-finite
floats normalising to zero, an unknown chunk written after `PSCR` still being skipped, and a
live `PapyrusWorldRuntime`'s state surviving a save and a restore.

`openskyTests/OpenSkySaveTimerTests.swift` covers `PTMR` the same way: a timer-state round
trip, byte-level determinism, an absent chunk meaning no pending timers, an empty timer
list writing the same bytes as omitting the parameter entirely, a truncated entry, a
truncated duration, a bogus timer count, an unknown slot byte, non-finite and negative
durations normalising to zero, an unknown chunk written after `PTMR` still being skipped,
and a live `PapyrusWorldRuntime`'s pending timers surviving a save and a restore.

Related: [Runtime reference identity and world state](/engine/runtime-state.md) for the
store and snapshot this format serializes, [FormID and TES4 header](/formats/formid.md) for
the HEDR statistics behind the fingerprint and for the raw FormID in an interior cell
location, and [ESM/ESP plugin container](/formats/esm.md) for the plugin files the load
order names.

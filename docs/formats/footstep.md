---
type: File Format
title: Footstep records
description: Skyrim SE FSTP, FSTS, IPDS, and IPCT fields, the reversed XCNT/DATA
  ordering of a footstep set, ARMA.SNDD, and the tag-to-sound chain OpenSky walks.
tags: [format, plugin, audio, footstep]
timestamp: 2026-08-04T00:00:00Z
---

# Footstep records

OpenSky decodes `FSTP` footsteps, `FSTS` footstep sets, and the `IPDS`/`IPCT` impact pair
they resolve through, from the [ESM container](/formats/esm.md). Together they answer one
question: when the player's behavior graph fires the event `FootLeft`, which sound plays?

The field inventory follows the UESP
[`FSTP`](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/FSTP),
[`FSTS`](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/FSTS),
[`IPDS`](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/IPDS), and
[`IPCT`](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/IPCT) pages. Field widths,
signedness, and array order are cross-checked against xEdit `dev-4.1.6`
[`wbDefinitionsTES5.pas`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsTES5.pas)
(`wbRecord(FSTP, ...)` and `wbRecord(FSTS, ...)` at lines 7093-7124, `ARMA`'s `SNDD` at
line 4216) and against a read-only `Skyrim.esm` probe on 2026-08-04.

## Contents

- The chain
- `FSTP` footstep
- `FSTS` footstep set
- Why `XCNT` and `DATA` disagree about order
- `IPDS` impact data set
- `IPCT` impact
- `ARMA.SNDD` — which set an actor walks with
- What vanilla actually holds
- Surface material

## The chain

```text
behavior-graph event name ("FootLeft")
  -> FSTP whose ANAM tag matches, inside the FSTS list for the current gait
  -> IPDS the footstep's DATA names
  -> IPCT paired with the material under the foot
  -> SNDR the impact's SNAM names
  -> the audio file to play
```

Every link is optional in the data, so every link is optional in the decoder. The runtime
that walks it is the [footstep director](/engine/audio.md).

## `FSTP` footstep

| field | on-disk type | decoded value |
| --- | --- | --- |
| `EDID` | zstring | optional editor ID |
| `DATA` | FormID | optional `IPDS` impact data set |
| `ANAM` | zstring | the tag the behavior graph raises |

The tag is not an `AACT` action and not a free-form label: it is spelled exactly as
`0_master.hkx` declares the event. Vanilla uses twenty distinct tags across all 116 `FSTP`
records — `FootLeft`, `FootRight`, `FootLeft2`, `FootRight2`, `FootScuffLeft`,
`FootScuffRight`, `FootSprintLeft`, `FootSprintRight`, `JumpUp`, `JumpDown`, the
quadruped `FootFront`/`FootBack` pair, and a handful of creature-specific tags such as
`NPCWolfBark` and `NPCFoxBreatheRun`. Footsteps are how vanilla plays a dog's bark and a
wolf's breathing too, which is why the record is a general animation-tag hook rather than
a boots-on-stone one.

## `FSTS` footstep set

| field | on-disk type | decoded value |
| --- | --- | --- |
| `EDID` | zstring | optional editor ID |
| `XCNT` | 5 x uint32, 20 bytes | walking, running, sprinting, sneaking, swimming counts |
| `DATA` | FormID[] | swimming, sneaking, sprinting, running, walking arrays, end to end |

## Why `XCNT` and `DATA` disagree about order

`XCNT` lists its five counts walk-first. The `DATA` arrays those counts size are laid out
swim-first. UESP documents `XCNT`'s order and describes `DATA` only as "end-to-end `FSTP`
formids"; xEdit's `wbStruct(DATA, 'Footsteps', ...)` spells out the array order, and the
install agrees with xEdit.

`NPCWerewolfFootstepSet` (`000F23E6`) is the record that settles it. Its `XCNT` is
`[4, 4, 4, 0, 0]` and its `DATA` carries 12 FormIDs. Reading `DATA` swim-first puts the
werewolf's own `NPCWerewolfFootJumpUpFootstep` and `NPCWerewolfFootJumpDownFootstep` in
the walking list, beside its walk footsteps. Reading `DATA` walk-first puts the *sprint*
footsteps in the walking list and the default human jump sounds beside them. Only the
first reading is coherent, and it is what `FootstepSet.split` implements.

Defensively, counts that do not add up to the FormIDs actually present truncate: each list
takes what is left, and surplus FormIDs are dropped. A malformed set costs the actor its
footsteps, not the load.

## `IPDS` impact data set

| field | on-disk type | decoded value |
| --- | --- | --- |
| `EDID` | zstring | optional editor ID |
| `PNAM` | 2 x FormID, 8 bytes | `MATT` material type, `IPCT` impact to play on it; repeats |

Vanilla sets carry one pair per material the Creation Kit knows about — 64 to 78 of them
in the 220 sets `Skyrim.esm` holds. A pair naming a null impact and a `PNAM` shorter than
8 bytes are both skipped rather than throwing.

## `IPCT` impact

| field | on-disk type | decoded value |
| --- | --- | --- |
| `EDID` | zstring | optional editor ID |
| `SNAM` | FormID | optional primary sound descriptor (`SNDR`) |
| `NAM1` | FormID | optional secondary sound descriptor (`SNDR`) |

The record also carries the visual half of an impact — `MODL` model, `DODT` decal, `DNAM`
and `ENAM` texture sets, `NAM2` hazard, and a `DATA` struct of effect duration, angle
threshold, placement radius and sound level. None of it is decoded: nothing draws an
impact yet, and a field this decoder does not read cannot go stale against the spec.

## `ARMA.SNDD` — which set an actor walks with

`ARMA` gains one field: `SNDD`, a `FSTS` FormID (xEdit
`wbFormIDCk(SNDD, 'Footstep Sound', [FSTS, NULL])`). The armature on an actor's feet
decides how that actor sounds, which is why bare feet, light boots and heavy boots differ
without the engine choosing anything. 174 of the install's 766 `ARMA` records declare one.
See [actor records](/formats/actors.md) for the rest of `ARMA`.

## What vanilla actually holds

Read-only `Skyrim.esm` probe, 2026-08-04, through `openskycli footstep`:

| record | count |
| --- | --- |
| `FSTS` | 35 |
| `FSTP` | 116 |
| `IPDS` | 220 |
| `IPCT` | 515 |
| `ARMA` with `SNDD` | 174 |

The humanoid sets are `DefaultFootstepSet` (`00012F16`), `FSTBarefootFootstepSet`
(`00021468`), `FSTArmorLightFootstepSet` (`00021486`) and `FSTArmorHeavyFootstepSet`
(`00021487`); the remaining 31 are creatures. Every humanoid set carries six footsteps per
gait — a left and a right step, a left and a right scuff, and the two jump tags — and an
empty swimming list, so a swimming player is silent underfoot in vanilla data as well as
in OpenSky.

The resolved sound files are `.wav`, not `.xwm`: `DefaultFootstepSet`'s walking `FootLeft`
reaches `sound\fx\fst\npc\stonesolid\walk\l\fst_npc_stonesolid_walk_01.wav`. That is why
issue #352 also added the [WAVE reader](/formats/wav.md) — the chain resolved cleanly to a
container the audio engine could not play.

## Surface material

The `IPDS` table is indexed by `MATT` material type, and the surface under the foot supplies
it (issue #358). The chain that produces it is documented in
[material types](/formats/material-type.md); the short version is that a collision mesh
names its material by hashing the Creation Kit name, exterior ground names it through the
winning `LTEX`'s `MNAM`, and both resolve to one `MATT` FormID at cell-build time.

`WalkController.groundMaterial` is where it surfaces: the material of the flattest walkable
contact, or of the terrain vertex the capsule was snapped to. The renderer's audio tick
hands it to `WorldAudioFootstepDirector.handleGraphEvents`, which passes it to
`FootstepStore.resolve(tag:gait:in:material:)`. Snow, wood, grass and gravel are four
different sounds because they are four different `PNAM` pairs.

`ImpactDataSet.impact(for:)` still answers a nil material with the table's *representative*
impact: the most frequently paired `IPCT`, ties broken by record order. That path is no
longer the normal case but it is not dead — an airborne player, a mesh carrying a material
value no `MATT` hashes to, and a landscape texture with no `MNAM` all reach it. It is a
measurement of what the authored table mostly says rather than a hardcoded material, and
for a set whose entries all agree — what UESP means by "generally the same for all" — it
returns that one impact exactly. For the vanilla humanoid sets it is the stone-solid impact.

A material the table has no pair for falls back the same way. Vanilla `IPDS` tables carry a
pair per material the Creation Kit knows about, so this is rare; walking the `MATT` `PNAM`
parent chain to find a broader match would be the next refinement, and nothing does it yet.

`FootstepRealDataTests` is the env-gated evidence that the whole chain holds against the
install: every tag in every non-swimming gait of the four humanoid sets resolves to a
`SNDR` with a track, every one of those tracks is RIFF/WAVE and decodes to a buffer, the
vanilla `Player`'s iron boots select `FSTArmorHeavyFootstepSet`, and walking the real
`0_master.hkx` over the launch cell's real terrain fires tags the default set answers to.
Run it with `make realtest T='FootstepRealDataTests/...'`.

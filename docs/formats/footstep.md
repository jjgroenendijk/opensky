---
type: File Format
title: Footstep records
description: Skyrim SE FSTP, FSTS, IPDS, and IPCT fields, the reversed XCNT and DATA order of
  a footstep set, ARMA SNDD, and the chain from animation tag to sound.
tags: [format, plugin, audio, footstep]
---

# Footstep records

When the player's behavior graph sends the event `FootLeft`, which sound plays? Four records
answer this: `FSTP` footstep, `FSTS` footstep set, and the impact pair `IPDS` and `IPCT`.

Sources: UESP [`FSTP`](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/FSTP),
[`FSTS`](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/FSTS),
[`IPDS`](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/IPDS), and
[`IPCT`](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/IPCT). Field sizes, signs, and
array order checked against xEdit `dev-4.1.6`
[`wbDefinitionsTES5.pas`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsTES5.pas)
(`wbRecord(FSTP, ...)` and `wbRecord(FSTS, ...)` at lines 7093-7124, `ARMA SNDD` at line
4216) and against `Skyrim.esm`.

## The chain

```text
behavior graph event name ("FootLeft")
  -> FSTP with that ANAM tag, in the FSTS list for the current gait
  -> IPDS named by the footstep's DATA
  -> IPCT paired with the material under the foot
  -> SNDR named by the impact's SNAM
  -> the sound file
```

Every link may be missing in the data. See [audio](/engine/audio.md) for the runtime.

## FSTP

| Field | Type | Meaning |
| --- | --- | --- |
| `EDID` | zstring | Editor ID |
| `DATA` | FormID | Impact data set (`IPDS`) |
| `ANAM` | zstring | Tag that the behavior graph sends |

The tag is spelled exactly like the event in `0_master.hkx`. It is not an `AACT` action.
Vanilla has 20 tags across its 116 `FSTP` records, for example `FootLeft`, `FootRight`,
`FootLeft2`, `FootScuffLeft`, `FootSprintLeft`, `JumpUp`, `JumpDown`, the four-legged
`FootFront` and `FootBack`, and creature tags such as `NPCWolfBark` and `NPCFoxBreatheRun`.
So a footstep is a general "sound on animation tag" hook. Vanilla uses it for a dog's bark
too.

## FSTS

| Field | Type | Meaning |
| --- | --- | --- |
| `EDID` | zstring | Editor ID |
| `XCNT` | 5 x uint32 | Counts: walking, running, sprinting, sneaking, swimming |
| `DATA` | FormID list | Lists: swimming, sneaking, sprinting, running, walking, end to end |

### XCNT and DATA use opposite orders

`XCNT` lists its counts with walking first. `DATA` stores the lists with swimming first.
UESP gives the `XCNT` order but calls `DATA` only "end-to-end `FSTP` formids". xEdit's
`wbStruct(DATA, 'Footsteps', ...)` gives the list order, and the game data agrees with
xEdit.

`NPCWerewolfFootstepSet` (`000F23E6`) proves it. Its `XCNT` is `[4, 4, 4, 0, 0]`, and its
`DATA` has 12 FormIDs. Read swimming first, the walking list holds the werewolf's own walk
steps and its `NPCWerewolfFootJumpUpFootstep` and `NPCWerewolfFootJumpDownFootstep`. Read
walking first, the walking list holds sprint steps and the default human jump sounds. Only
the first reading makes sense.

If the counts do not match the FormIDs present, each list takes what is left, and extra
FormIDs are dropped. A broken set costs the actor its footsteps, not the load.

## IPDS

| Field | Type | Meaning |
| --- | --- | --- |
| `EDID` | zstring | Editor ID |
| `PNAM` | 2 x FormID | Material (`MATT`) and the impact (`IPCT`) to play on it. Repeats |

Vanilla sets have one pair for each material the Creation Kit knows, 64 to 78 pairs per
set. A pair with a null impact, or a `PNAM` shorter than 8 bytes, is skipped.

If there is no material (for example the player is in the air), or the table has no pair
for the material, OpenSky uses the set's most common impact. Ties go to record order. For
a set where every entry is the same, which UESP calls "generally the same for all", this is
exactly that impact. For the vanilla humanoid sets, it is the solid stone impact. The
`MATT` parent chain could give a closer match, but OpenSky does not follow it yet.

## IPCT

| Field | Type | Meaning |
| --- | --- | --- |
| `EDID` | zstring | Editor ID |
| `SNAM` | FormID | Main sound (`SNDR`) |
| `NAM1` | FormID | Second sound (`SNDR`) |

`IPCT` also holds the visual part of an impact: `MODL` model, `DODT` decal, `DNAM` and
`ENAM` texture sets, `NAM2` hazard, and a `DATA` struct (effect duration, angle threshold,
placement radius, sound level). OpenSky draws the model and the `DNAM` decal
([impacts and decals](/rendering/decals.md)). It does not use `ENAM`, `NAM2`, the angle
threshold, or the placement radius.

## ARMA SNDD

`ARMA SNDD` is an `FSTS` FormID (xEdit `wbFormIDCk(SNDD, 'Footstep Sound', [FSTS, NULL])`).
The armor on an actor's feet decides how the actor sounds. That is why bare feet, light
boots, and heavy boots sound different. In vanilla, 174 of 766 `ARMA` records have one. See
[actor records](/formats/actors.md).

## Surface material

The `IPDS` table is keyed by material, and the surface under the foot gives the material.
A collision mesh names its material by a hash of the Creation Kit name. Exterior ground
names it through the `MNAM` of the winning `LTEX`. Both lead to one `MATT` FormID. See
[material types](/formats/material-type.md). Snow, wood, grass, and gravel sound different
because they are different `PNAM` pairs.

## Vanilla Skyrim.esm

`openskycli footstep` shows these records.

| Record | Count |
| --- | --- |
| `FSTS` | 35 |
| `FSTP` | 116 |
| `IPDS` | 220 |
| `IPCT` | 515 |
| `ARMA` with `SNDD` | 174 |

The humanoid sets are `DefaultFootstepSet` (`00012F16`), `FSTBarefootFootstepSet`
(`00021468`), `FSTArmorLightFootstepSet` (`00021486`), and `FSTArmorHeavyFootstepSet`
(`00021487`). The other 31 are creatures. Each humanoid set has six footsteps per gait: a
left and right step, a left and right scuff, and the two jump tags. The swimming list is
empty, so a swimming player makes no footstep sound in vanilla either.

The sound files are `.wav`, not `.xwm`. For example, the walking `FootLeft` of
`DefaultFootstepSet` plays
`sound\fx\fst\npc\stonesolid\walk\l\fst_npc_stonesolid_walk_01.wav`. See
[WAV](/formats/wav.md). The vanilla `Player` wears iron boots, so it uses
`FSTArmorHeavyFootstepSet`.

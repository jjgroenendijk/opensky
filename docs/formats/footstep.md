---
type: File Format
title: Footstep records
description: FSTP, FSTS, IPDS, and IPCT fields, the reversed XCNT and DATA order in a footstep
  set, ARMA.SNDD, and the chain from animation tag to sound.
tags: [format, plugin, audio, footstep]
---

# Footstep records

These records answer one question: when the player's animation raises the event `FootLeft`,
which sound plays?

Sources: UESP [`FSTP`](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/FSTP),
[`FSTS`](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/FSTS),
[`IPDS`](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/IPDS), and
[`IPCT`](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/IPCT). Sizes, signs, and array
order checked against xEdit `dev-4.1.6`
[`wbDefinitionsTES5.pas`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsTES5.pas)
(`FSTP` and `FSTS` at lines 7093-7124, `ARMA SNDD` at line 4216) and against `Skyrim.esm`.

## The chain

```text
animation event name ("FootLeft")
  -> FSTP with that ANAM tag, in the FSTS list for the current gait
  -> IPDS named by the footstep's DATA
  -> IPCT paired with the material under the foot
  -> SNDR named by the impact's SNAM
  -> the sound file
```

Every link can be missing in the data. The runtime that walks the chain is described on the
[audio](/engine/audio.md) page.

## FSTP footstep

| Field | Type | Meaning |
| --- | --- | --- |
| `EDID` | zstring | Editor ID |
| `DATA` | FormID | Impact data set (`IPDS`) |
| `ANAM` | zstring | The event tag |

The tag is spelled exactly as `0_master.hkx` names the animation event. Vanilla uses twenty
tags, for example `FootLeft`, `FootRight`, `FootScuffLeft`, `FootSprintLeft`, `JumpUp`,
`JumpDown`, `FootFront` and `FootBack` for four-legged creatures, and creature tags such as
`NPCWolfBark` and `NPCFoxBreatheRun`. So footsteps are a general hook for sounds tied to
animation, not only for feet.

## FSTS footstep set

| Field | Type | Meaning |
| --- | --- | --- |
| `EDID` | zstring | Editor ID |
| `XCNT` | 5 x uint32 | Counts: walking, running, sprinting, sneaking, swimming |
| `DATA` | FormID list | Lists: swimming, sneaking, sprinting, running, walking |

## XCNT and DATA use opposite orders

`XCNT` lists its counts walking first. `DATA` stores its lists swimming first. UESP gives the
`XCNT` order but calls `DATA` only "end-to-end `FSTP` formids". xEdit's
`wbStruct(DATA, 'Footsteps', ...)` gives the `DATA` order, and the real data agrees with
xEdit.

`NPCWerewolfFootstepSet` (`000F23E6`) proves it. Its `XCNT` is `[4, 4, 4, 0, 0]`, and `DATA`
has 12 FormIDs.

- Read `DATA` swimming first: the walking list holds the werewolf's own walk steps and its
  `NPCWerewolfFootJumpUpFootstep` and `NPCWerewolfFootJumpDownFootstep`. This makes sense.
- Read `DATA` walking first: the walking list holds sprint steps and the default human jump
  sounds. This does not.

When the counts do not add up to the FormIDs present, each list takes what is left, and
extra FormIDs are dropped. A broken set costs the actor its footsteps, not the whole load.

## IPDS impact data set

| Field | Type | Meaning |
| --- | --- | --- |
| `EDID` | zstring | Editor ID |
| `PNAM` | 2 x FormID | A material (`MATT`) and the impact (`IPCT`) for it. Repeats |

A vanilla set has one pair for each material the Creation Kit knows, 64 to 78 pairs. A pair
with a null impact, or a `PNAM` shorter than 8 bytes, is skipped.

## IPCT impact

| Field | Type | Meaning |
| --- | --- | --- |
| `EDID` | zstring | Editor ID |
| `SNAM` | FormID | Main sound (`SNDR`) |
| `NAM1` | FormID | Second sound (`SNDR`) |

`IPCT` also holds the visual part of an impact: `MODL` model, `DODT` decal, `DNAM` and `ENAM`
texture sets, `NAM2` hazard, and a `DATA` struct (duration, angle, radius, sound level).
OpenSky does not read these yet.

## ARMA.SNDD

`ARMA SNDD` is an `FSTS` FormID (xEdit: `wbFormIDCk(SNDD, 'Footstep Sound', [FSTS, NULL])`).
The armor on an actor's feet decides how the actor sounds. That is why bare feet, light
boots, and heavy boots sound different. See [actor records](/formats/actors.md) for the rest
of `ARMA`.

## Vanilla sets

`openskycli footstep` prints the chain from `Skyrim.esm`.

The four human sets are `DefaultFootstepSet` (`00012F16`), `FSTBarefootFootstepSet`
(`00021468`), `FSTArmorLightFootstepSet` (`00021486`), and `FSTArmorHeavyFootstepSet`
(`00021487`). All other sets are for creatures. Each human set has six footsteps per gait:
left and right step, left and right scuff, and the two jump tags. The swimming list is
empty, so a swimming player makes no footstep sound in vanilla either.

The sound files are `.wav`, not `.xwm`. Example: walking `FootLeft` in `DefaultFootstepSet`
reaches `sound\fx\fst\npc\stonesolid\walk\l\fst_npc_stonesolid_walk_01.wav`. See
[WAV](/formats/wav.md).

## Surface material

The `IPDS` table is keyed by material (`MATT`). The ground under the foot gives the
material. A collision mesh names it by a hash, and terrain names it through `LTEX.MNAM`. See
[material types](/formats/material-type.md). The walk controller reports the material of the
flattest walkable contact, or of the terrain point under the player.

With no material, the set uses its representative impact: the `IPCT` that appears in the
most pairs, with ties broken by record order. This happens when the player is in the air,
when a mesh's material hash matches no `MATT`, or when a landscape texture has no `MNAM`.
UESP says the entries are "generally the same for all", and for the vanilla human sets the
representative impact is stone.

A material with no pair in the table falls back the same way. Following the `MATT PNAM`
parent chain would find a closer match, but OpenSky does not do that yet.

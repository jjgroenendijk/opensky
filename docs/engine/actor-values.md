---
type: Subsystem
title: Actor values
description: How OpenSky derives an actor's health, magicka and stamina from records, tracks
  the current values at runtime, regenerates them, saves them, and drives the HUD meters.
tags: [engine, actors, gameplay, stats, health, magicka, stamina, hud, runtime-state]
timestamp: 2026-08-07T00:00:00Z
---

# Actor values

Roadmap item 15.3 (issue #194). The three primary actor values — health, magicka,
stamina — from the records that author them to the vanilla HUD bars that show
them. Skills, resistances and the rest of the actor-value table are M18; this
subsystem deliberately does not pretend to be the general store those will need.

Impl: `opensky/Engine/Actors/`, plus `opensky/Engine/UI/HUDMeterBinding.swift`
and `opensky/App/GameViewControllerActorValues.swift`. Record layouts:
[actor records](/formats/actors.md). The store underneath:
[runtime state](/engine/runtime-state.md).

## Contents

* Shape of the subsystem
* Derivation
* The apportionment rule
* Where the numbers were checked
* Runtime store
* Regeneration
* HUD meters
* Persistence
* Panel seam
* Out of scope

## Shape of the subsystem

Five types, split along the same line every other gameplay subsystem here is
split along — records on one side, runtime state on the other, and nothing
crossing.

| type | role |
| --- | --- |
| `ActorValues` | one health/magicka/stamina triple, with clamping and fractions |
| `ActorValueDerivation` | the documented formula: records -> base maximums |
| `ActorValueResolver` | walks the template chain and looks up RACE and CLAS |
| `ActorValueBaselineResolver` | what a subject's values are before anything touches them |
| `ActorValueRuntime` | damage, restore, regeneration on top of `WorldStateStore` |

The record side is immutable and buildable once per load order. The runtime side
is `@MainActor`, mutable, and knows nothing about records — it asks the baseline
resolver for maximums and never derives one itself. That is the
`InventoryBaselineResolver` / `InventoryRuntime` split, applied again.

## Derivation

Every rule is quoted from an open source. Nothing is inferred from memory, and
the two constants come from GMSTs rather than from literals.

Without the ACBS auto-calc flag:

```text
value = race starting attribute + ACBS offset
```

"If the auto-calc flag for an NPC isn't set, all attributes are calculated just
as: Attribute = [Racial bonus] + [NPC offset]."
(<https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/CLAS>)

With it:

```text
magicka = race + offset + share(iAVDhmsLevelUp * (level - 1), class weights)
stamina = same
health  = same + fNPCHealthLevelBonus * (level - 1)
```

"Attribute = [Racial bonus] + [NPC offset] + 10\*(Level-1)/(Sum of class'
attribute weights)\*[Attribute weight]", and "The only difference for health is
that health always receives an additional 5 points per level, regardless of the
class weights". (Same page.) The Creation Kit names the two constants: "all
Actors gain 10 points to distribute per level (this value comes from the
iAVDhmsLevelUp game setting) ... NPC's get a bonus amount of health per level as
set by the fNPCHealthLevelBonus game setting; by default this is 5."
(<https://ck.uesp.net/wiki/Class>) `Skyrim.esm` authors both at their documented
defaults, which `ActorValueRealDataTests` pins.

Level comes from the ACBS level word. A `PC Level Mult` actor multiplies the
player's level by that word over 1000 and clamps to Calc Min / Calc Max
(<https://ck.uesp.net/wiki/Stats_Tab>); a zero bound means unbounded, because
that is what the Creation Kit leaves when a designer sets no clamp. There is no
player level before M18, so callers pass 1 and every scaled actor resolves at the
bottom of its range — deliberately the low end rather than a guess at the middle.

The auto-calc flag is implied by PC Level Mult: "Note that if PC Level Mult is
checked, Auto Calc Stats will always be checked." (Same page.)

A negative offset can out-weigh a small racial base; the result floors at zero,
because the game has no concept of a negative maximum and one would make every
fraction the HUD asks for meaningless.

## The apportionment rule

The per-level spread is not a multiply-and-round. UESP states "the exact method":
hand out every complete set of points first — `floor(points / sum of weights) *
weight` each — then give the leftover out one at a time, looping over the
attributes "ordered first in decreasing order of weight" with ties broken "in
reverse actor value index order (stamina, magicka, then health)", never taking an
attribute past its own weight in a single pass.

The Creation Kit's worked example uses the opposite tie order (health first) but
reaches the same numbers on every case documented on either page, because ties
only matter when the leftover runs out mid-pass. Where they diverge OpenSky
follows UESP, which states its rule as the exact method rather than as a
procedure for hand-calculation.

Every point is handed out, so the three results always sum to the points
available. A class with no weights spreads nothing rather than dividing by zero,
which would put a NaN into an actor's maximum health.

## Where the numbers were checked

The formula is not trusted on the strength of its citations alone. The Creation
Kit bakes its own calculated health, magicka and stamina into every NPC_'s DNAM
(see [actor records](/formats/actors.md)), which is an independent statement of
the answer. `ActorValueRealDataTests` derives values for every auto-calc,
non-PC-level-mult NPC_ in `Skyrim.esm` and compares: **4297 records compared,
4271 exact, 26 explained**.

The 26 all inherit their stats from one template, `EncBandit04TemplateMelee`
(`0001E60D`), whose DNAM contradicts its own ACBS: `NordRace`'s 50 starting
health plus its own +125 offset is 175, and its DNAM says 170. Its sibling
`EncBandit03TemplateMelee` matches the same formula exactly, so the formula is
not what differs — the baked value is stale, which the Creation Kit documents can
happen: "one must refresh the Stats Tab (click on another tab then back to the
Stats Tab) to update Calculated Health, Magicka, and Stamina if Attribute Offsets
or underlying Race or Class Base Attributes change."
(<https://ck.uesp.net/wiki/Stats_Tab>) The test pins the count at 26 rather than
merely tolerating a mismatch, so a load order that changes it says so.

Getting from 61 mismatches to 26 is what established the `statsRace` rule
documented under [template resolution](/formats/actors.md).

`openskycli actor-values --npc <formid-or-edid>` prints one actor's derivation
with the record each input came from; `--race <formid-or-edid>` prints one race's
starting attributes and regen rates. Both are read-only.

## Runtime store

`ActorValueState` is a `WorldStateComponentKind` (`.actorValues`) holding
**current values only**. The maximums are a pure function of the RACE, CLAS and
NPC_ records, so storing them would let a save keep a number a changed load order
no longer authors. That is the rule the inventory and quest baselines already
follow: re-derive, never persist.

One invariant, enforced in `init` rather than checked at use sites: every value
is finite and not negative. That is what lets the runtime, the HUD and the save
each assume it separately, and it is why the save decoder can hand corrupt floats
straight to the initializer.

`hasZeroHealth` is derived, not stored. A stored flag and a stored health can
disagree, and after a save round trip there would be no way to say which was
right. Item 15.6 consumes it; this layer does not act on it.

Nothing in `ActorValueRuntime` throws. A damage amount that is negative or NaN is
ignored, an unknown subject falls back to a documented baseline, and every write
is clamped. Runtime state is not file parsing — there is no malformed input to
reject, and an actor that cannot be hit because a mutation threw is a worse
outcome than one that takes a clamped hit.

A rejected mutation writes nothing at all. `state(of:)` hands back a full
baseline for an untouched actor, so without that guard a zero-damage call would
write the baseline back and mark a clean reference dirty.

The player has no record in this engine (`ReferenceKey.player`), so its baseline
comes from a configured race, and from a documented fallback until character
generation exists (M18). That fallback is 100/100/100 — probed, not remembered:
every playable vanilla race authors 50/50/50, and the vanilla `Player` record
(`00000007`) adds +50 to each through its ACBS offsets.

## Regeneration

Rates come from RACE DATA, quoted from the Creation Kit: "Health Regen: The
percentage of total Health that is regenerated each second"
(<https://ck.uesp.net/wiki/Race>). So one step adds
`maximum * percent / 100 * step`, with no accumulated per-actor drift.

Regeneration advances on a 1/60 s fixed step, matching the Papyrus VM's, and
chains onto the same `Renderer.onWorldUpdate` closure. That is what makes the
menu-pause rule apply for free: the renderer gates the delta through its
`FrameSimClock`, a paused frame delivers zero, and a zero delta advances nothing,
regenerates nothing, and is safe to call every frame. A negative or non-finite
delta is treated the same way rather than run backwards. A long stall is capped
at eight steps per call so it cannot spiral into minutes of catch-up.

Order is deterministic: the runtime sorts holders by `ReferenceKey`, so a set of
actors ends in the same state whichever order they were collected in.

Health does not regenerate at zero. An actor at zero health is dead or in
bleedout, and both are item 15.6's to decide; silently healing one back to life
here would make that decision on its behalf.

Only the player and the resident actors regenerate. An actor in a cell that is
not loaded is not simulated at all in this engine, and walking every dirty
reference in the store each frame would cost real time for a number nobody can
observe.

## HUD meters

The M8 bars stop being a static placeholder here, with no SWF work at all. The
engine-side `HUDMeterBinding` turns current values plus maximums into the
existing `HUDMeterValues` and gates on change, so a static HUD is not re-rendered
sixty times a second; the controller hands whatever comes out of it to
`HUDMovieBridge.setMeters(_:runtime:)`.

The derivation lives in the engine rather than in the AppKit controller because
the acceptance gate drives player damage headlessly and watches the meters
change through the meter contract, which is only possible without a window or an
SWF runtime if the binding is an engine type.

An actor with a zero maximum reads an empty bar rather than a full one: that is
the one reading a player must not be given.

## Persistence

A new save chunk, `AVAL`, one entry per actor whose values deviate from a full
baseline: key, cell, then three float32 current values in health-magicka-stamina
order. Additive and split out of `RDLT` for the same reason `INVN`, `SPWN`,
`QSTS` and `QALS` are — a component kind inside `RDLT` is versioned by
`formatVersion`, so an older build would refuse every save containing a wounded
actor instead of loading the rest of the world with everyone at full health. A
session in which nothing took damage writes no chunk at all. Layout:
[OpenSky save container](/formats/opensky-save.md).

Because the maximums are not written, a save restored against changed records
gets the records' numbers: the stored current value survives, and the first
mutation clamps it into the new range.

## Panel seam

`ActorValueControlProviding` is the contract a Combat panel is written against:
live readouts for the player and the nearest resident actor — current, maximums,
regen rates, level, whether auto-calc applied, and the zero-health flag — plus
damage, restore, refill and reset controls with a player / nearest-actor target
selector. `GameViewController` conforms to it now; the panel itself ships with
the M15 acceptance gate (item 15.9). Writing the conformance now is what proves
the runtime can answer the questions a panel asks: every field is a plain read
off `ActorValueRuntime`, with no accounting invented at the UI.

## Out of scope

Weapon damage application (items 15.4, 15.5), death and ragdoll (15.6), Papyrus
and condition exposure (15.8), skills and leveling (M18+). The bleedout ratio is
decoded off CLAS already so 15.6 does not have to re-open the record; nothing in
this item reads it.

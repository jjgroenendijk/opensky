---
type: Subsystem
title: Actor values
description: How OpenSky derives every actor value from records, stores the whole 164-entry
  table at runtime as offsets plus modifier slots, regenerates and saves them, answers
  resistance queries, writes them from Papyrus, and drives the HUD meters.
tags: [engine, actors, gameplay, stats, health, magicka, stamina, resistances, skills, hud,
  runtime-state]
timestamp: 2026-08-19T00:00:00Z
---

# Actor values

Roadmap items 15.3 (issue #194), 19.5 (issue #468) and 20.3 (issue #496). The
three primary actor values — health, magicka, stamina — from the records that
author them to the vanilla HUD bars that show them, plus the override store that
holds all 164 entries of the vanilla actor-value table, resistances included, and
the three Papyrus natives that write them.

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
* The override table
* The precedence rule
* Writing an actor value from Papyrus
* Baselines for the non-primary values
* Resistances
* Regeneration
* HUD meters
* Persistence
* Panel seam
* Naming an actor value
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
| `ActorValueEntry` | one value as a caller reads it: an absolute base plus three modifiers |
| `ActorValueOverride` | one value as the store holds it: a base *offset* plus three modifiers |
| `ActorValueReadable` | the lookup rule a condition and a native snapshot share |
| `CharacterClassStore` | load-order-wide CLAS lookup the derivation reads its weights from |

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

## The override table

Item 19.5 (issue #468) stored the other 161 actor values; item 20.3 (issue #496)
brought the three primaries into the same table. `ActorValueState` carries a
sparse `[Int32: ActorValueOverride]` keyed by vanilla table index, beside the
typed `current` triple the primaries keep.

Sparse is the design rather than an optimization. An actor has 164 actor values
and a session touches a handful; a dense table would put a number in the save
for every value a record authors, which is the same "re-derive, never persist"
rule the maximums follow. An index absent from the table reads its baseline, and
an override that comes back to nothing is dropped rather than kept at zero — an
actor whose fire resistance was raised and then lowered again is an actor nothing
happened to.

Each override is a base **offset** plus three modifier slots. The offset is what
makes one table safe for all 164 values and is the subject of the precedence rule
below; the slot vocabulary is the scripting surface's own: "While GetActorValue
returns the current value, SetActorValue sets the base value ... Any modifiers are
left intact."
(<https://ck.uesp.net/wiki/SetActorValue_-_Actor>)

| slot | written by | persisted |
| --- | --- | --- |
| `baseOffset` | `SetActorValue`, a skill advance, an attribute pick | yes |
| `permanent` | `ModActorValue` and `ForceActorValue` | yes |
| `temporary` | an active magic effect, item 19.6 | no — the effect re-establishes it |
| `damage` | `DamageActorValue`; never positive | yes |

`ActorValueEntry` is the *resolved* view of an override — an absolute base plus
the same three modifiers — and it is what every caller reads. The store composes
one from the baseline on the way out and decomposes it on the way back in, so
nothing outside `ActorValueState` has to know that a stored base is a distance.

The current value of a non-primary is derived, never stored, for the reason
`hasZeroHealth` is: a stored current and a stored base can disagree, and after a
save round trip there is no way to say which was right. Damage moves the damage
slot and floors the current value at zero; restoring moves it back toward zero and
stops there, so a restore can never lift a value above what its base and modifiers
say.

A primary is the one value whose current number *is* stored, in `current`. That is
15.3's design and it is not re-opened: the HUD, the save, the combat damage path
and the death latch all read it directly. What item 20.3 adds is the ceiling above
it:

```text
base(primary)    = derived maximum + baseOffset
maximum(primary) = base + permanent + temporary
current(primary) = the stored number, clamped into 0 ... maximum
```

The damage *slot* is therefore never written for a primary — its damage is already
the gap between `current` and `maximum` — and a write that moves a primary's
maximum moves `current` by the same amount. That is the documented behaviour rather
than an invention: "ModActorValue is distinct from DamageActorValue because it
adjusts the maximum value for the AV, while DamageActorValue or RestoreActorValue
only adjust the current value. For example, if an actor has 100 Health,
ModActorValue by -10 will lower the health total to 90/90, whereas DamageActorValue
by 10 will result in 90/100 Health."
(<https://ck.uesp.net/wiki/ModActorValue_-_Actor>) Damage already taken survives the
change: an actor at 90/100 modified by -10 reads 80/90, neither healed by the change
nor charged twice for it.

Regeneration fills toward the effective maximum and rewrites the whole component
every step, carrying the override table through, so a buff is not dropped on the
next frame. A refill fills to the effective maximum and keeps the table: a
fortified actor filled to the top is full at its fortified maximum rather than
stripped of the buff. "Reset to records" is what drops the table, which is what
makes it the deliberate way back.

`ActorValueRuntime` addresses everything by index: `value(at:on:)`,
`baseValue(at:on:)`, `damage(at:by:on:)`, `restore(at:by:on:)`,
`setValue(at:to:on:)`, `setBase(at:to:on:)`, `incrementBase(at:by:on:)`,
`advanceSkill(at:by:on:)`, `forceValue(at:to:on:)` and the two modifier writes.
Only an index outside the table answers nil.

## The precedence rule

**A base override is a delta on top of the re-derived baseline, never a
replacement for it.** The records stay authoritative for what an actor value is;
the store says only what the session did to it, and the two are added on every
read.

That one sentence decides every case the subsystem could otherwise get wrong:

* A level change, a race change or a reordered load order re-derives the
  baseline, and every actor value moves with it. Nothing pins a number a plugin
  no longer authors, which is the rule the maximums have followed since 15.3.
* A trained or script-set value is never clobbered by that re-derivation, because
  it was stored as the distance and not as the number.
* A trained value still *gains* from a level-up, because the derived half moved
  underneath it. Item 20.5's skill advancement and item 20.6's attribute picks
  both need exactly this: a skill trained by five points is five points above
  whatever the records now author, and neither half can silently eat the other.
* An override of zero is not stored, so an actor that ended where it started is
  clean in the save and in the dirty counts.

The alternative — storing an absolute base that suppresses derivation for that
slot — was rejected for the second half of that third point. It keeps a trained
skill safe, but it also freezes it: a level-up would raise the derived skill
underneath a pinned number and change nothing the actor reads, and a load order
that rebalanced a race would be invisible to every actor a session had touched.

`incrementBase(at:by:on:)` is the API item 20.5 writes through, and
`advanceSkill(at:by:on:)` is the same call with a guard that the index is one of
the eighteen skills — a skill advance that lands on `Aggression` because a caller
had an off-by-one index is a bug worth failing loudly at the one call site that
only ever means a skill.

## Writing an actor value from Papyrus

Three natives write, and all three were deliberately unregistered until the
primaries had a store to write to (`PapyrusNativeActorValues.swift`):

| native | writes | quoted behaviour |
| --- | --- | --- |
| `SetActorValue` | the base offset | "Sets the base value ... Any modifiers are left intact." |
| `ModActorValue` | the permanent modifier | "adjusts the maximum value for the AV" |
| `ForceActorValue` | the permanent modifier | forces the *current* value to the number asked for |

`ForceActorValue`'s worked example is transcribed as a unit test, because it pins
the whole model in one paragraph: "If an actor has a base health of 125 and you
force their health to 0, then the permanent modifier will be set to -125, and
their current health will become 0. If you then set the base health to 150, they
will still have a permanent modifier of -125, so their current health will
instantly become 25 (150 - 125)."
(<https://ck.uesp.net/wiki/ForceActorValue_-_Actor>) OpenSky answers 0/0 and then
25/25 for that sequence.

A negative argument passes through rather than being taken as a magnitude, which
is the opposite of what `DamageActorValue` does and is deliberate: the wiki's own
`ModActorValue` example modifies health by -10. A health that reaches zero through
any of the three becomes a death on the same call, exactly as a fatal blow does,
so a script that forces health to zero and then asks `IsDead()` does not read a
live actor lying on the floor. `SetAV`, `ModAV` and `ForceAV` are Papyrus-level
wrappers and need no registration of their own.

## Baselines for the non-primary values

An untouched value reads a baseline, and the baseline comes from records where
records author one:

| actor value | source |
| --- | --- |
| the eighteen skills (6–23) | 15 + RACE DATA skill bonus + the class spread |
| `Speed Mult` (30) | NPC_ ACBS 0x0E "Speed Multiplier" |
| `Carry Weight` (32) | RACE DATA 0x30 "Base Carry Weight" |
| `Unarmed Damage` (35) | RACE DATA 0x60 "Unarmed Damage" |
| `Mass` (36) | RACE DATA 0x34 "Base Mass" |
| everything else | the documented default, which is 0 |

The skill formula is quoted: "Skill = 15 + [Racial bonus] +
8\*(Level-1)/(Sum of class' skill weights)\*[Skill weight]"
(<https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/CLAS>), with the leftover
points handed out "one at a time by looping over all the skills in order ...
ordered first by their weight (higher skills ordered first) and second by their
actor value index (lower indices are ordered first)". Note that tie rule is the
*opposite* of the attribute one, which breaks ties in reverse index order; both
are transcribed as stated rather than unified. The 8 comes from
`iAVDSkillsLevelUp`, which `Skyrim.esm` authors at exactly that.

Zero for everything else is a position, not a placeholder. An actor value is an
accumulator: a resistance nothing grants is 0%, a bonus nothing confers is +0,
and an AI attribute the AIDT does not author is the bottom of its enumeration.
The two values vanilla starts away from zero come from their own record fields
above, so an actor with **no** record behind it — a summon — reads 0 for mass and
carry weight and 100 for speed. That is a stated gap.

NPC_ DNAM carries "18 base skills, 18 skill mods". OpenSky does not read them:
no open source distinguishes the two arrays, and the CLAS formula is itself
stated as approximate ("generally only be accurate to within a couple points"),
so neither settles how they combine. Storing a number whose provenance is
unresolved is worse than reading the documented floor; the DNAM block waits for
M20's skill work with a real-data comparison behind it.

`ActorValueRealDataTests` pins the derivation against the install:
`NordRace` yields Two-Handed +10 and One-Handed, Block, Smithing, Light Armor and
Speech +5, which is exactly what UESP documents for the race, and every playable
race authors 300 carry weight, mass 1 and a 35-point bonus budget.
`openskycli actor-values --npc <editor-id>` and `--race <editor-id>` print the
whole derived table with the record each value came from.

## Resistances

`ActorValueResistance.swift` is the one place the cap and the composition rule
live, so items 19.8 and 19.9 call a function rather than each re-deriving a
formula. A resistance actor value holds percentage points, and MGEF names the
value an effect is resisted by in its DATA "Resistance Actor Value" field, which
is why the query takes an index rather than an enumeration of damage types.

The cap is 85%, and only for the player: "Resist Magic is capped at 85%. The cap
only applies to you; followers and enemies with 100% resistance are truly immune."
(<https://en.uesp.net/wiki/Skyrim:Resist_Magic>) Resist Poison is capped the same
way (<https://en.uesp.net/wiki/Skyrim:Resist_Poison>); Resist Disease is not —
"Resist Disease 100% provides disease immunity ... values above 100% provide no
additional benefit" (<https://en.uesp.net/wiki/Skyrim:Resist_Disease>).

That cap is an OpenSky constant rather than a game setting, and that is a probed
fact: the install's whole resolved game-setting table carries no resistance cap
under any editor ID (2026-08-16, `openskycli gmst list` — 1649 settings, the only
two matching "resist" are the strings `sMagicEffectResisted` and
`sNormalWeaponsResisted`). No plugin can move the number, so it is stated with
its source the way [detection](/engine/detection.md) states its own constants.

Composition is multiplicative with Resist Magic first: "a 100-point Fire Damage
spell would deal only 15 points of damage with Resist Magic 85%; Resist Fire 85%
would then reduce the 15 points by a further 85% to 2.25 points of final damage"
(same page). `magicDamageMultiplier(element:on:)` is that sentence, and the unit
test asserts exactly those 2.25 points.

A **negative** resistance is a weakness and passes through negative, which is the
whole of the weakness mechanic (issue #471). UESP words Weakness to Fire as
"Target is `<mag>`% weaker to fire damage"
(<https://en.uesp.net/wiki/Skyrim:Weakness_to_Fire>) and vanilla authors it as a
detrimental Value Modifier on `Resist Fire`, so a target at -30 points reads a
fraction of -0.3 and takes 130% damage. There is no floor, because no source
states one — the cap bounds the resistant end alone — and two weaknesses compound
through the same multiplicative composition, which is what the same page's
"Weakness to fire is strengthened by weakness to magic" describes.

`Damage Resist` (39) is deliberately **not** a percentage resistance. It is an
armor rating with its own formula and its own 80% cap, which the install does
carry as a game setting (`fMaxArmorRating = 80`). Feeding it to the percentage
query would read 40 points of armor as 40% resistance, so the query rejects it
and it belongs with the armor formula when that lands.

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

The regeneration step rewrites the whole component every frame and carries the
override table through that write, so a temporary modifier an active effect is
holding survives a tick ([magic](/engine/magic.md)).

Because the maximums are not written, a save restored against changed records
gets the records' numbers: the stored current value survives, and the first
mutation clamps it into the new range.

The override table travels in its own chunk, `AVOV` (item 20.3): key, cell, a
value count, then one `(index, baseOffset, permanent, damage)` record per stored
value. It is a sibling of `AVAL` rather than an extension of it for the reason
`QALS` is a sibling of `QSTS` — `AVAL` entries are a flat positional layout with
no per-entry length, so appending a variable-length list would make an older
build misparse the whole chunk instead of skipping the new part. The temporary
modifier is not written, because the magic effect that established it is what
re-establishes it — item 19.6 landed that half, and `ActiveEffectRuntime`
rebuilds the slot from the `AEFF` chunk on load ([magic](/engine/magic.md)) — and
persisting both would double the buff on every reload. An `AVOV` entry always
travels beside the actor's `AVAL` entry, so the decoder never has to invent a
health for an actor whose health the save did not carry; an orphan entry is
dropped.

`AVOV` replaces item 19.5's `AVGN`, which carried an absolute base for the 161
non-primary values. The tag changed rather than the payload's meaning because the
two layouts have identical shapes and different ones: reading an `AVGN` record as
an `AVOV` record would turn a resistance of 30 into a resistance 30 points *above*
what the records say. An `AVGN` chunk is now an unknown tag and is skipped, so an
older save restores every actor at its record baselines.

## Panel seam

`ActorValueControlProviding` is the contract a Combat panel is written against:
live readouts for the player and the nearest resident actor — current, maximums,
regen rates, level, whether auto-calc applied, and the zero-health flag — plus
damage, restore, refill and reset controls with a player / nearest-actor target
selector. `GameViewController` conforms to it, and every field is a plain read
off `ActorValueRuntime` with no accounting invented at the UI.

## Verification surface

`World > Combat & Physics > Actor Values` (`Destination-combatPhysics`,
`PanelSection-combatActorValues`), shipped with the M15 acceptance gate
(issue #198).

| Control | Id | Does |
| --- | --- | --- |
| Target | `ActorValueTargetControl` | picks the player or the nearest resident actor |
| Value | `ActorValueKindControl` | picks health, magicka or stamina |
| Other value | `ActorValueNameControl` | any of the other 161, by vanilla name or index; wins over the popup |
| Amount | `ActorValueAmountControl` | the number the three buttons apply |
| Damage | `ActorValueDamageControl` | takes that amount off the selected value |
| Restore | `ActorValueRestoreControl` | adds it back, capped at the derived maximum |
| Set | `ActorValueSetControl` | writes the amount outright: the current value for a primary, the base for everything else |
| Set base | `ActorValueSetBaseControl` | writes the amount as the value's *base*, which for a primary moves the maximum the bar is drawn against |
| Refill | `ActorValueRefillControl` | returns every bar to its maximum |
| Reset to records | `ActorValueResetControl` | drops the runtime state so the actor derives from records again |
| Readout | `CombatActorValuesStatsLabel` | both actors' three bars, the derivation that produced the maximums, the selected value with its modifier slots and capped resistance fraction, and the last action |

The bars are drawn against the *effective* maximum since item 20.3, so a base
write or a fortify shows on them rather than only in the selection line, and the
selection line answers for a primary too — a health at 90/90 after a
`ModActorValue` and one at 90/100 after a `DamageActorValue` are different states
that the bar alone cannot tell apart.

The amount is a text field rather than a slider because a gate that damages an
actor by exactly 40 has to be able to ask for exactly 40, and a field holding
something that is not a number falls back to the documented default rather than
sending a NaN into the runtime. The section is not overridable: a damaged actor
is world state, and "Reset to records" is the deliberate way back rather than a
sidebar reset that would refill every bar in the cell.

"Other value" is a text field rather than a 164-row popup for the same reason:
typing `Resist Fire`, `ResistFire` or `41` all reach the same value, and a
picker with 164 rows is worse than a field for every one of them. A field
holding something that names no actor value falls back to the popup rather than
acting on a guess, and the readout's selected-value line is what shows which one
won.

Readout lines are formatted by `ActorValueControlReadout` in the engine target,
where a unit test can reach them without a window.

## Naming an actor value

Two surfaces address actor values by *vanilla identity* rather than by
`ActorValueKind`, and they spell that identity differently: a CTDA parameter
carries a signed index, and a Papyrus native carries a name string.
`opensky/Engine/Actors/ActorValueIdentity.swift` (issue #375, item 15.8) holds
the one mapping both use.

The table is xEdit's `wbActorValueEnum`, dev-4.1.6 `Core/wbDefinitionsTES5.pas`,
reproduced verbatim: 0 `Aggression` through 163 `Reflect Damage`, with -1 spelled
`None`. The `Unknown NN` placeholders xEdit carries for the indices Skyrim leaves
unnamed are kept, because a table that renumbered around a gap would put every
later index one off. Health is 24, magicka 25 and stamina 26 because that file
says so, not because anything here recalled it.

Names are matched with every non-alphanumeric character removed and the rest
lowercased, so xEdit's `One-Handed`, Papyrus's `OneHanded` and a script's
`"one handed"` are one name. Papyrus does use a few *different* words for the
same value — `Marksman` for index 8, which xEdit spells `Archery` — and
`index(named:)` deliberately still does not alias those, so the measured miss
buckets below do not move.

Three vanilla AVIF records carry editor ids in that same legacy vocabulary —
`AVMarksman`, `AVSpeechcraft` and `AVMysticism` — and those three *are* mapped,
by `recordNameAliases` behind the separate `index(recordName:)` entry point that
only [actor value information](/formats/actor-value-information.md) calls. The
mapping is observed rather than asserted: each record's own FULL string resolves
through Skyrim.esm's string table to `Archery`, `Speech` and `Illusion`, and
`ActorValueInformationRealDataTests` pins exactly that.

Since item 19.5 every entry in the table is stored, so `kind(at:)` answers a
*fast-path* question rather than a can-I-read-it question: nil means "this value
has no separately stored current number", and `isVanilla(index:)` is what says
whether an index names an actor value at all. Since item 20.3 the fast path is
narrower still — a primary and a resistance take the same route for a base or a
modifier write, and differ only in where the current value lives. Only an index
outside the table is still a miss — a
reason-tagged false and a `ConditionTally` bucket on the condition side, a
tallied native failure and the call's declared default on the Papyrus side.

That change is measured rather than asserted. `Skyrim.esm` authors 607
`GetActorValue` / `GetActorValuePercent` conditions; 68 name a primary and 539
name one of the other actor values, so 539 tallied misses became 539 answers, and
`everyActorValueConditionInSkyrimESMResolvesItsParameter` pins the remaining miss
bucket at empty.

Papyrus names are matched the same way, so `GetActorValue("ResistFire")` answers.
The synonyms `index(named:)` deliberately does not alias — `Marksman` for
`Archery` — still fail there, and now that failure means only "no vanilla actor
value carries this name", which is the tally's whole remaining content.

## Out of scope

Weapon damage application (items 15.4, 15.5), death and ragdoll (15.6), skill
use and skill experience (item 20.5), the level curve and attribute picks (item
20.6), perk state (item 20.4). Item 20.3 builds the write path those three
consume and stops there: nothing here decides when a skill should rise. A timed
Recover effect on a primary is still counted rather than applied, which is issue
511 — the storage it was waiting for now exists, and lifting the guard moves
tallies that need re-measuring against the install ([magic](/engine/magic.md)).

AVIF record decode landed with item 20.1 — the record adds metadata, not values;
see [actor value information](/formats/actor-value-information.md). Papyrus and
condition exposure landed with item 15.8 — see
[the Papyrus VM](/engine/papyrus-vm.md) and
[conditions](/formats/conditions.md). The bleedout ratio is
decoded off CLAS already so 15.6 does not have to re-open the record; nothing in
this item reads it.

---
type: Subsystem
title: Melee combat
description: Draw and sheath, attack and block, hit volumes, damage and impact sounds —
  driven by the behavior graph's own events rather than by an engine-side timer.
tags: [engine, combat, melee, behavior-graph, weapons, damage, gmst]
timestamp: 2026-08-07T00:00:00Z
---

# Melee combat

Roadmap item 15.4 (issue #195). A swing from the key press to the health that
comes off. Archery is 15.5, death and ragdolls are 15.6, hostility and the
opponent that swings back are 15.7, and enchantments and critical-hit perks are
M18.

Impl: `opensky/Engine/Combat/`, plus `opensky/App/GameViewControllerMelee.swift`
and its two satellites. The graph underneath:
[behavior graph runtime](/engine/behavior-runtime.md). The sweep it borrows:
[dynamic rigid bodies](/engine/dynamic-bodies.md). The health it takes off:
[actor values](/engine/actor-values.md).

## Contents

* [The rule: the graph decides, the engine asks](#the-rule-the-graph-decides-the-engine-asks)
* [The event seam, now multi-consumer](#the-event-seam-now-multi-consumer)
* [Census-named events and variables](#census-named-events-and-variables)
* [Hand types: what each hand is holding](#hand-types-what-each-hand-is-holding)
* [Draw and sheath](#draw-and-sheath)
* [Attack phase](#attack-phase)
* [Reach and the hit volume](#reach-and-the-hit-volume)
* [Target filtering](#target-filtering)
* [Damage and the block formula](#damage-and-the-block-formula)
* [Stagger](#stagger)
* [Impact sound](#impact-sound)
* [Input bindings](#input-bindings)
* [The two M14 feature tallies, revisited](#the-two-m14-feature-tallies-revisited)
* [What the vanilla graph actually does](#what-the-vanilla-graph-actually-does)
* [Verification surface](#verification-surface)

## The rule: the graph decides, the engine asks

The engine raises `attackStart`. It does not decide that an attack began. The
behavior graph decides whether an attack state was entered, how long the windup
lasts, and which frame connects, and it says so by firing events back. So every
melee state in this subsystem is *read* off the graph rather than timed beside
it.

That is the same rule the [footstep director](/engine/world-sfx.md) follows and
it is the same reasoning: a phase invented from a clock drifts against the
animation the player is watching, and a hit resolved off that clock lands at a
moment the swing is not at. It also means there is no engine-side swing timer to
cancel — a stagger that takes the attack state away takes the phase with it, for
free.

One frame of melee, in order:

1. `MeleeCombatRuntime.acceptFrame(_:)` turns intent edges into raised events.
2. The fixed steps advance the graph, which is `LocomotionBridge`'s job.
3. `MeleeCombatRuntime.handleGraphEvents(_:)` advances `MeleeCombatState` on the
   drained names and, on the contact frame, runs the sweep and applies damage.

## The event seam, now multi-consumer

`LocomotionGraphEventQueue` was a drain-once queue with one consumer, the
footstep director. A drain-once queue cannot have two: whichever drained first
would take the whole batch and the other would see an empty list.

It now holds one cursor per registered consumer. Each consumer sees every fired
name exactly once, in fire order, whatever order the consumers drain in and
however many frames apart they do it. Cursors are positions in a monotonic
sequence rather than indices into the storage, so trimming the front cannot
silently rewind or advance anybody, and a name is dropped once every consumer
has read past it.

The bound (64) is over the *undrained* names, so a consumer that stops draining
costs the other nothing but its own lost tail. With no consumer registered the
buffer is dropped outright, which is why `LocomotionBridge` registers both
cursors in `init` rather than lazily: a cursor created on first drain would find
the queue already empty.

`LocomotionBridge.footstepEventConsumer` and `.meleeEventConsumer` are the two,
owned by the bridge so they travel with it — the renderer holds the bridge as a
settable property, and a cursor stored beside it would point into the previous
bridge's queue after a reassignment.

## Census-named events and variables

Every name comes from the M14 behavior census over the install
(`logs/hkx-behavior-census.log`, produced by `HKBBehaviorCensusRealDataTests`),
never from memory. `0_master.hkx` declares 230 variables and 1,217 events and a
merely plausible name resolves to nothing at all. `CombatGraphNames` quotes each
exactly as the third-person `meshes\actors\character\behaviors\0_master.hkx`
spells it, including the inconsistent capitalization vanilla actually uses —
`attackStart` is lower-camel and `HitFrame` is upper-camel, in the same file.

Havok events have no direction: the same name can be raised into a graph and
fired back out of it. The split below records which side of the seam OpenSky
uses each name on, not a property of the data.

| Raised into the graph | Meaning |
| --- | --- |
| `weaponDraw`, `weaponSheathe` | unsheathe and sheathe requests |
| `WeapEquip`, `Magic_Equip`, `Unequip` | the equip events the graph transitions on |
| `attackStart`, `attackRelease`, `attackStop` | swing start, held-power release, swing end |
| `blockStart`, `blockStop` | guard up and down |
| `staggerStart`, `staggerStop` | the stagger a landed hit inflicts, on the *target's* graph |

| Fired back by the graph | Meaning |
| --- | --- |
| `BeginWeaponDraw`, `BeginWeaponSheathe` | the clip annotations where the weapon changes nodes |
| `WeapEquip_Out`, `Unequip_Out` | the graph's own end-of-equip transitions |
| `weaponSwing` | the swing's audible start, ahead of contact |
| `preHitFrame` | the frame before contact |
| `HitFrame` | the contact frame, which runs the sweep |
| `blockHitStart` | a block absorbed a hit |

Variables written: `IsAttacking`, `IsBlocking`, `IsStaggering`,
`staggerMagnitude`, `weaponSpeedMult`, `iRightHandType`, `iLeftHandType`.

`weaponDraw` is the odd one in the raised list: the graph declares it but no
transition in any file under `meshes\actors\character\behaviors\` names it. In
vanilla it is the *intent*, and the engine — not the graph — decides what that
intent equips and raises the matching equip event. OpenSky raises both, in that
order, so the intent is still on the wire for anything listening and the graph
gets the event it acts on. `Magic_Equip` replaces `WeapEquip` when the right
hand holds a readied spell; `Unequip` covers both branches on the way back.

Variables are written before events are raised, the same order the stagger path
uses: the graph picks the equip clip off `iRightHandType` when it acts on
`WeapEquip`, so a frame that equips a sword and draws it at once must write the
number first.

## Hand types: what each hand is holding

`iRightHandType` and `iLeftHandType` are `int32` and they select the animation
set. The equip selectors in `weapequip.hkx` index their child list straight off
them, and most of the combat transitions in `1hm_behavior.hkx` are conditioned
on them, so an unwritten pair leaves both hands reading zero — empty — and the
graph plays the hand-to-hand branch for a drawn sword.

The M14 census gave the two names and their type but not the encoding. Issue #403
settled it by reading the install rather than guessing, and `CombatHandType`
carries both the numbers and the citation:

| Value | Holding | Read from |
| --- | --- | --- |
| 0 | nothing (hand-to-hand) | `Weap_Equip_MSG` child 0, `MT_H2H_State` |
| 1 | one-handed sword | `1HM_Equip.hkx`, `MT_1HM_State` |
| 2 | dagger | `Dag_Equip.hkx`, `MT_Dagger_State` |
| 3 | war axe | `Axe_Equip.hkx`, `MT_Axe_State` |
| 4 | mace | `Mac_Equip.hkx`, `MT_Mace_State` |
| 5 | greatsword | `2HC_Equip.hkx`, `MT_2HM_State` |
| 6 | battleaxe or warhammer | `2HW_Equip.hkx`, `MT_2HW_State` |
| 7 | bow | `Bow_Equip.hkx`, `MT_BowState` |
| 8 | staff | `Stf_Equip.hkx`, `MT_Staff_State` |
| 9 | readied spell | `MagicForceEquipBlend`, `MT_Magic_State` |
| 10 | shield | `MRh_and_Shield_ForceEquipBlend`, `MT_Shield_State` |
| 11 | torch | `MRh_Equip_TorchBlend`, `MT_Torch_State` |
| 12 | crossbow | `DLC01\CrossBow_Equip.hkx`, `MT_CrossBowState` |

Three independent readings agree on it. `weapequip.hkx` binds
`hkbManualSelectorGenerator::m_selectedGeneratorIndex` to the variable, so the
selector's child list *is* the encoding in order. `0_master.hkx` names the same
thirteen values as the state ids of its `MT_LeftHandOverride` machine. And the
transition conditions agree where they overlap: `1hm_behavior.hkx` takes
`bowAttackStart` only on `iRightHandType == 7`, bashes with a bow or crossbow on
`(iRightHandType == 7) || (iRightHandType == 12)`, dual-wields only when both
hands sit in `1...4`, and `magicbehavior.hkx` shouts on `(iRightHandType == 8)
|| (iRightHandType == 9)`.

This is **not** the WEAP DNAM animation type, which is the trap: the two agree
on 0 through 8 and then diverge, because DNAM spells crossbow 9 while the graph
spells spell 9 and crossbow 12, and the graph carries three values (spell,
shield, torch) that no WEAP record can hold. `CombatHandType.init(weapon:)` is
that conversion and is the only place the two enums meet.

The left hand is resolved from the equipped set in
`GameViewController.equippedHands()`: a two-handed weapon fills both hands and
reports its own type on each, a second equipped WEAP is the off-hand one, and a
shield is any equipped ARMO taking biped slot 39. A torch is a LIGH, which the
equipment catalog does not index, so a lit hand still reports empty; torches and
real dual-wield need the equipment runtime to track *which* hand an item went
into, which is M18's.

## Draw and sheath

Four states, and the two interim ones are the point:

| State | Weapon rides |
| --- | --- |
| `sheathed` | the sheathed node |
| `drawing` | the sheathed node |
| `drawn` | the hand node (`Weapon`) |
| `sheathing` | the hand node |

The attachment moves on the clip annotation, not on the request. `weaponDraw`
puts the state in `drawing` and the weapon stays where it was; `BeginWeaponDraw`
arrives when the hand has reached it, and that is the frame the model changes
nodes. Sheathing is the mirror. The node names are in
[actor records](/formats/actors.md); `RigidAttachment` does the rewrite.

Not every equip clip carries that annotation. `1HM_Equip.hkx`, `Bow_Equip.hkx`
and `CrossBow_Equip.hkx` do, at time 0.0; `Dag_Equip.hkx`, `Axe_Equip.hkx`,
`Mac_Equip.hkx`, `2HC_Equip.hkx` and `2HW_Equip.hkx` carry no such mark at all
and only tag `weaponDraw` mid-clip, which is ambiguous with the engine's own
raise of the same name. So the graph's `WeapEquip_Out` — the transition
`0_master.hkx` takes into `Weap_Readied_State` — is observed as a second way in,
and `Unequip_Out` as the mirror. The annotation is the early one and wins when a
clip has it; the transition is the backstop that keeps a dagger from being stuck
mid-draw forever. Whichever arrives first moves the attachment, once.

An annotation authored *at* the clip's first frame is the reason
[clip annotations](/engine/behavior-runtime.md) now cover a closed interval on
the update that seeds a clip: under the half-open rule every later update uses,
`BeginWeaponDraw` at 0.0 could never fire.

## Attack phase

`idle` -> `windup` (`attackStart`) -> `swinging` (`preHitFrame`) -> `contact`
(`HitFrame`) -> `recovery` -> `idle` (`attackStop`).

The hit window is `contact` alone. `preHitFrame` exists to say a hit is
imminent, so a consumer that wants to pre-resolve something has a frame to do it
in, and the sweep still runs on the contact frame itself. `recovery` is entered
by `endFrame()`, called once per frame after the batch, so a swing that fires
`HitFrame` and nothing else does not sit in the hit window forever.

A sheath or a `staggerStart` drops the phase straight to `idle`, and no new
swing starts from a sheathed weapon or while a stagger plays.

## Reach and the hit volume

Reach is the documented combat-distance formula:

```text
reach = fCombatDistance * actorScale * WEAP.reach
```

UESP "Skyrim Mod:Mod File Format/WEAP" states it verbatim for DNAM offset
`0x08` ("For melee weapons, this is a multiplier used in the reach formula:
`fCombatDistance * NPCScale * WeaponReach`"), and xEdit's
`wbDefinitionsTES5.pas` names the same DNAM member at the same offset. Nothing
here is measured, so nothing here needs a measurement recorded. `fCombatDistance`
resolves to 141.000 on the local install; `openskycli gmst combat` prints it and
the block settings with the plugin each came from.

The swing volume is a `ShapeSweepQuery` — the 15.2 sweep type — because a swing
is a blade segment travelling along an arc and a swept capsule is that segment's
conservative hull. The arc is **not** reconstructed from the animation pose: a
hit resolved from one sampled frame of a 30 Hz clip lands wherever that frame
happened to be, and the contact frame is a single annotation rather than a
window. The volume is built from the attacker's facing at the contact frame,
which is what the player aimed, and the blade segment gives it the vertical
extent a point query would miss.

Two numbers in that volume are **OpenSky decisions**, not documented values —
vanilla's hit volume lives in its own code and is not readable from the install:

* vertical half-extent = 0.25 x capsule height, centred on the chest. Covers a
  target on the same floor without reaching one standing on a table.
* radius = 0.75 x capsule radius. Stands in for the arc's horizontal width
  rather than for the steel.

Narrowphase is capsule against capsule: the shortest distance between two
segments against the sum of the radii, which is exact. That is the one place a
sweep against *actors* differs from `ShapeSweeper`, which answers against placed
static geometry and grows triangles and hulls to do it. The sweep is sampled at
24 steps with no bisection: 15.2 refines the touch distance because a tunneling
guard needs the exact moment of contact, whereas a swing needs to know *whether*
it connected and roughly where.

## Target filtering

1. **Actors only.** The caller supplies the target list, so a barrel is never in
   it; `MeleeHitDetector` does not know what a barrel is.
2. **Never the attacker.** Matched on `ReferenceKey`, not on distance — an
   attacker whose own capsule the swing starts inside would otherwise be the
   nearest thing to it every time.
3. **At most one hit per swing per target.** Held by swing id rather than by
   time, so a graph firing two contact annotations in one attack (the census
   shows `2_HitFrame` beside `HitFrame`) still lands one hit, while the next
   swing hits the same target again.

Every target the swing reaches is returned, not just the nearest: a two-handed
sweep through a crowd hits the crowd, and picking one would be a gameplay rule
invented here rather than read from anywhere. Order is nearest first, ties broken
on the lower reference.

## Damage and the block formula

Unblocked damage is WEAP DATA base damage. Blocking reduces it, and the formula's
*shape* is UESP "Skyrim:Block", quoted rather than paraphrased:

```text
weapon: blocked = fBlockWeaponBase
                  + fBlockWeaponScaling * attackerWeaponBaseDamage
                    * (1 + blockSkill * fBlockSkillMult / 100) / 100
shield: blocked = fShieldBaseFactor
                  + fShieldScalingFactor * shieldBaseArmorRating
                    * (1 + blockSkill * fBlockSkillMult / 100) / 100
```

then multiplied by the Shield Wall perk term, the Fortify Block enchantment and
potion terms, and by `fBlockPowerAttackMult` for a power attack, and finally
capped at `fBlockMax`.

The formula's *numbers* are the install's, and **they are not the ones UESP
prints**. Read from `Skyrim.esm` on 2026-08-07 through `openskycli gmst combat`:

| Setting | Install | UESP |
| --- | --- | --- |
| `fCombatDistance` | 141.000 | 141 |
| `fBlockWeaponBase` | 0.300 | 30 |
| `fBlockWeaponScaling` | 0.200 | 0.2 |
| `fShieldBaseFactor` | 0.450 | 45 |
| `fShieldScalingFactor` | 0.200 | 0.2 |
| `fBlockSkillMult` | 2.000 | 1.5 |
| `fBlockMax` | 0.700 | 85% |
| `fBlockPowerAttackMult` | 0.660 | 0.66 |

The install wins: these are the numbers the shipped game reads. What UESP still
supplies, and what the raw values cannot, is which term multiplies which — and
that shape reconciles with the fractions on exactly one reading, the one
implemented: the two base terms and the cap are fractions, and the two scaling
terms are percentage points per unit of damage or armour, so each carries a
`/ 100`. Every quantity `MeleeDamage` returns is a fraction in `0...1`; the
readout multiplies by 100 at the very end.

Two terms are absent by scope. Perks and Fortify Block effects are M18 — there
is no perk tree and no magic effect to read them from — so they enter as one
`bonusMultiplier` defaulting to 1, which is what the formula reduces to for a
character with neither. Block *skill* is in the same position: `ActorValues`
carries health, magicka and stamina only, so `blockSkill` is a parameter
defaulting to 15, the starting value UESP gives.

One reading looks like a bug and is not: the weapon branch scales on the
*attacker's* weapon damage, not the blocker's. UESP is explicit and works
through the creature case (an unarmed attacker gives the flat base) to show it
is intended. Reading it the other way would make a warhammer the best thing to
block with.

## Stagger

A landed hit whose weapon carries DNAM `stagger` writes `staggerMagnitude` on the
target's graph and then raises `staggerStart` on it — write then raise, so the
stagger behavior reads *this* hit's magnitude rather than the previous one's,
which is the order the locomotion bridge already uses for every step.

Only the player has a behavior graph in this milestone, so a stagger raised on an
NPC answers false and the trace records the hit as not staggered. That is the
truth rather than a silent no-op; the actor that swings back is 15.7's.

## Impact sound

The footstep chain with one link changed, and reusing it rather than building a
second one is the point:

```text
footstep: graph event -> FSTP tag  -> IPDS -> IPCT for the material -> SNDR
melee:    HitFrame    -> WEAP INAM -> IPDS -> IPCT for the material -> SNDR
```

From the IPDS onwards the two are identical, so `ImpactDataSet.impact(for:)` and
`Impact.sound` do the work exactly as they do for a footstep, and
`MeleeImpactResolver` reads its indexes straight off `FootstepStore`. WEAP
`INAM` is "Normal weapon swing impact set. Points to a IPDS" (UESP); `BIDS` is
the block-bash set and only a bash reads it. Both are decoded in
[records](/formats/records.md).

The material passed is the ground material under the player, not the material of
the body part that was struck: actors carry no per-body-part Havok material in
this engine, and the alternative is inventing one. Every link is optional — a
weapon with no INAM, an IPDS with no entry, an IPCT with no sound — and each
ends the walk with a silent hit rather than a throw. Decals and visual effects
are out of scope.

## Input bindings

| Key | Action | Shape |
| --- | --- | --- |
| `R` | draw / sheath | one-shot latch, one binding for both directions |
| Left mouse | attack | one-shot latch (the first click still captures the cursor) |
| Right mouse | block | held, raised on its edges |

All three flow `GameMetalView` -> `CameraInputState` -> `CameraInput` ->
`LocomotionBridge.meleeIntent` -> `MeleeCombatRuntime`, which is the same path
sneak, sprint and jump take; there is no second input route.

`meleeIntent` is split out of `LocomotionIntent` because nothing in the fixed
step reads it. Attacking does not move the capsule — the graph does that, if its
attack clips carry travel — so the melee runtime consumes it at frame rate and
the locomotion step never sees it.

Losing cursor capture drops the guard, because a block held through a lost
mouse-up would stay up forever. Whether the weapon is drawn survives, on the
same terms as sneak: it is world state the player set on purpose.

## The two M14 feature tallies, revisited

The issue asked whether the attack states need `clipUserControlled` and
`stateMachineTransitionInterrupted` implemented. Read against the evaluator, both
already are; the tally entries are observability, not gaps, and the coverage
delta is zero.

* `clipUserControlled` (79 evaluations): `BehaviorClipEvaluation` handles clip
  mode 2 by reading `m_userControlledTimeFraction` through the variable-bound
  member map and setting local time from it. That *is* the user-controlled
  semantics. The tally records that a mode-2 clip was evaluated so it stays
  visible.
* `stateMachineTransitionInterrupted` (61): `BehaviorStateMachineEvaluation`
  already starts the new transition from wherever the machine has got to and
  drops the older blend rather than nesting it, and honours
  `FLAG_UNINTERRUPTIBLE_WHILE_PLAYING`. Dropping the old blend is exactly what
  attack cancel and stagger interruption need, because the engine holds no swing
  timer that would keep running. The tally counts the drops.

## What the vanilla graph actually does

Probed on the local install 2026-08-07 through
`MeleeCombatRealDataTests`, headless, no window:

* Every raised event name and every written variable name resolves on the
  vanilla player graph — zero misses. Every observed name is declared too.
* Raising `weaponDraw` alone moved the graph but never reached an equip state,
  because no transition names it. Raising `WeapEquip` after it does: with
  `iRightHandType` set to 1, `weapequip.hkx` selects `1HM_Equip.hkx`, whose
  `BeginWeaponDraw` annotation arrives in the first drained batch, and the state
  reaches `drawn`.
* About a second later the graph fires `WeapEquip_Out` and enters
  `Weap_Readied_State`, which is what makes `1hm_behavior.hkx` reachable. A
  swing asked for before that has no attack state to enter and is dropped.
* From `Weap_Readied_State`, `attackStart` reaches an attack state and the graph
  fires `HitFrame`, so the sweep runs on the vanilla contact frame.

Every melee WEAP in the load order resolves a positive reach, and the INAM chain
reaches a real playable `.wav` for at least one of them.

## Verification surface

`World > Combat & Physics > Melee` (`Destination-combatPhysics`,
`PanelSection-combatMelee`). The section shipped under
`World > Player & Locomotion` and moved with the M15 gate (issue #198), which is
what that item's own note said would happen once the combat surface outgrew the
locomotion panel.

| Control | Id | Does |
| --- | --- | --- |
| Weapon drawn | `MeleeWeaponDrawnControl` | raises the draw or sheath event |
| Attack | `MeleeAttackControl` | requests exactly one swing |
| Clear hit trace | `MeleeClearTraceControl` | empties the trace and both counts |
| Readout | `CombatMeleeStatsLabel` | state, weapon and reach, both hand types, last-hit trace |

Block is a held modifier with nothing to latch — a checkbox would assert it for
a single frame and read as broken — so it is reported live in the state line
instead, on the same terms `LocomotionBindingsSection` reports run and sprint.
The section is not overridable: a drawn weapon is world state, not a panel
setting, and a "Reset all" that sheathed it would undo something the user did on
purpose.

The hands line names each hand and prints its number, so a wrong animation set
can be traced to the hand it came from rather than guessed at.

Covering tests: `MeleeCombatStateTests`, `CombatHandTypeTests`,
`MeleeHitDetectionTests`,
`MeleeDamageTests`, `MeleeCombatRuntimeTests`,
`LocomotionGraphEventFanOutTests`, and env-gated `MeleeCombatRealDataTests`.

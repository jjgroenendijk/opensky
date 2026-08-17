---
type: Subsystem
title: Magic and active effects
description: The runtime notion of a magic effect acting on an actor - the cited
  archetype semantics, the two timed behaviours the Recover flag selects, the
  component and its AEFF save chunk, condition gating, the stacking rules, the
  potion and ingredient consumption path, the caster runtime that knows spells,
  readies them to a hand and casts the self-delivery ones, and aimed delivery -
  spell projectiles through the archery pipeline, area application, and the
  resistance scaling a hostile magnitude pays on the way in.
tags: [engine, magic, effects, actors, alchemy, casting, spells, projectiles, resistances]
timestamp: 2026-08-17T00:00:00Z
---

# Magic and active effects

Roadmap item 19.6, issue #469. The first runtime magic in OpenSky: a decoded
[MGEF](/formats/magic-records.md) plus the EFIT numbers beside it becomes something acting
on an actor, moving that actor's [actor values](/engine/actor-values.md) and expiring on its
own. Casting is not here — issues 19.7 and 19.8 own that, and this subsystem applies effects
handed to it.

## Contents

- [Where the semantics come from](#where-the-semantics-come-from)
- [The two timed behaviours](#the-two-timed-behaviours)
- [Which archetypes are implemented](#which-archetypes-are-implemented)
- [The component](#the-component)
- [Ticking](#ticking)
- [Condition gating](#condition-gating)
- [Stacking](#stacking)
- [Consuming a potion or an ingredient](#consuming-a-potion-or-an-ingredient)
- [The AEFF save chunk](#the-aeff-save-chunk)
- [Casting](#casting)
- [The spellbook](#the-spellbook)
- [Readying a spell to a hand](#readying-a-spell-to-a-hand)
- [The cast loop](#the-cast-loop)
- [Abilities and powers](#abilities-and-powers)
- [Cast input and the animation seam](#cast-input-and-the-animation-seam)
- [The SPLB save chunk](#the-splb-save-chunk)
- [Delivery: casting at something else](#delivery-casting-at-something-else)
- [Spell projectiles](#spell-projectiles)
- [What a landed spell reaches](#what-a-landed-spell-reaches)
- [Resistances on hit](#resistances-on-hit)
- [Combat consequences](#combat-consequences)
- [Verification](#verification)
- [Limits / next](#limits--next)

| Layer | File | Target |
|---|---|---|
| Model | `opensky/Engine/Magic/ActiveEffect.swift` | app + CLI |
| Component | `opensky/Engine/Magic/ActiveEffectComponent.swift` | app + CLI |
| Archetype dispatch | `opensky/Engine/Magic/MagicEffectPlanner.swift` | app + CLI |
| Runtime | `opensky/Engine/Magic/ActiveEffectRuntime.swift` | app + CLI |
| Consumption | `opensky/Engine/Magic/MagicItemConsumption.swift` | app + CLI |
| Coverage tally | `opensky/Engine/Magic/ActiveEffectTally.swift` | app + CLI |
| Save chunk | `opensky/Engine/Formats/Save/OpenSkySave{Encoder,Decoder}ActiveEffects.swift` | app + CLI |
| Panel seam | `opensky/Engine/MagicEffectControlProviding.swift` and `MagicEffectControlReadout.swift` | app + CLI |
| Session wiring | `opensky/App/GameViewControllerMagic.swift` and `GameViewControllerMagicPanel.swift` | app |
| Verification surface | `opensky/App/Shell/Sections/CombatMagicEffectsSection.swift` | app |
| Spellbook component | `opensky/Engine/Magic/SpellbookComponent.swift` | app + CLI |
| Spellbook runtime | `opensky/Engine/Magic/SpellbookRuntime.swift` | app + CLI |
| Cast state machine | `opensky/Engine/Magic/CastingState.swift` | app + CLI |
| Cast loop | `opensky/Engine/Magic/CasterRuntime.swift` and `CasterRuntimeInput.swift` | app + CLI |
| Spellbook save chunk | `opensky/Engine/Formats/Save/OpenSkySave{Encoder,Decoder}Spellbook.swift` | app + CLI |
| Casting panel seam | `opensky/Engine/CastingControlProviding.swift` and `CastingControlReadout.swift` | app + CLI |
| Casting session wiring | `opensky/App/GameViewControllerCasting.swift` and `GameViewControllerCastingPanel.swift` | app |
| Casting verification surface | `opensky/App/Shell/Sections/CombatSpellcastingSection.swift` | app |
| Delivery routing | `opensky/Engine/Magic/CasterRuntimeDelivery.swift` | app + CLI |
| Landed-spell model and application | `opensky/Engine/Magic/SpellHit.swift` | app + CLI |
| Generalized shot | `opensky/Engine/Combat/ProjectileShot.swift` | app + CLI |
| Delivery session wiring | `opensky/App/GameViewControllerSpellDelivery.swift` | app |

## Where the semantics come from

Nothing on this page is recalled from memory. Two open sources carry the behaviour:

- The Creation Kit wiki's **Magic Effect** page, for the flags and the Effect Archetypes
  table (<https://ck.uesp.net/wiki/Magic_Effect>). The live host refuses automated
  requests, so it is read through the Wayback Machine — see
  [environment notes](/tools/environment.md).
- UESP's **Mod File Format/MGEF** page, for the DATA layout and the flag bits
  (<https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/MGEF>).
- UESP's **Alchemy Effects** page, for the ingredient rule
  (<https://en.uesp.net/wiki/Skyrim:Alchemy_Effects>).

Where a source hedges, the hedge is recorded rather than resolved by guessing; see
[Stacking](#stacking) and [Limits / next](#limits--next).

## The two timed behaviours

The Recover flag decides everything about how a timed effect works. The Creation Kit page
states it directly:

> Recover: When this Effect expires, the attribute returns to its previous state. If checked,
> Value Modifier and Peak Value Modifier archetypes will modify their actor value once at the
> start, then modify it back once the Effect expires; if unchecked, the actor value will get
> modified every second and will not be reset at the end. Note that for Magicka and Health,
> this works as follows: If checked, the Maximum and Current values are changed
> (buff/debuff). If unchecked, only current value is affected (heal/damage).

So `ActiveEffectMode` has exactly two cases:

- **`modifier`** (Recover set): the magnitude is added to the actor value's **temporary**
  modifier slot when the effect starts and subtracted again when it expires or is dispelled.
  Each stored effect records how much of the slot it owns, so two overlapping buffs hand back
  exactly what each of them put in.
- **`perSecond`** (Recover clear): the magnitude is paid into the value once per **completed**
  second and never taken back. A ten-second effect of magnitude two takes twenty points, the
  first two landing one second after it was applied. The count of seconds already paid is
  stored rather than derived from elapsed time alone, so repeated small ticks cannot round
  into an extra payment.

One arithmetic detail is stated because it is a real failure the suites caught rather than a
theoretical one: the simulation step is 1/60 s, which has no exact binary representation, so
sixty steps sum to slightly under one second. An effect is snapped to its duration once less
than half a step remains, and a whole second counts as paid within a millisecond of elapsing.
Without both, an effect would take one extra step to expire and a per-second effect would skip
its last pay-out.

A **zero-duration** effect is neither. It applies once and is stored nowhere, which is why
`ActiveEffectMode` has no `instant` case and why a restore-health potion never appears in the
active-effect list. Direction comes from the Detrimental flag — "This Effect is applied as a
negative value (damage) to the specified Actor Value" — so a detrimental effect routes
through `ActorValueRuntime.damage` and a restorative one through `restore`.

The No Magnitude, No Area and No Duration flags are deliberately ignored when applying. The
same page says why: "No Magnitude, No Area and No Duration do not actually affect the inner
workings of the effect, checking them just makes it so these parameters will be unavailable
when you assign the effect". The EFIT numbers are taken as authored.

## Which archetypes are implemented

Three, and every other archetype applies nothing and increments a per-archetype tally so the
unimplemented ground is measured rather than silent.

| Archetype | Cited behaviour | What OpenSky does |
|---|---|---|
| Value Modifier (0) | "Modifies the Actor Value by `<MAG>`." | One value, the MGEF's `PrimaryAV`, moved by the EFIT magnitude |
| Dual Value Modifier (5) | "The first value is modified by `<MAG>`, the second value is modified by `<MAG>` * AV Weight." | Two values, the second scaled by `SecondAVWeight` |
| Peak Value Modifier (34) | "1: The value to modify. 2: A keyword for effects it does not stack with." | One value plus the keyword the stacking rule compares |

Instant restore and damage are not separate archetypes: both are Value Modifier entries with
a zero duration, which is what the vanilla Restore Health and Damage Health effects are.

Two more reasons an implemented archetype still applies nothing, each its own tally bucket:

- The record names no actor value inside the vanilla table (usually -1, "none").
- A **timed Recover effect names health, magicka or stamina**. The Creation Kit says that
  changes both the maximum and the current value, and item 19.5 deliberately left the three
  primaries without the base-plus-modifiers storage the other 161 values have
  ([actor values](/engine/actor-values.md)), so there is nowhere to hold the change. It is
  counted rather than approximated: moving current health for a "fortify health" effect would
  be a different effect wearing the same name.

## The component

`ActiveEffectState` is a [world-state component](/engine/runtime-state.md) in the
`activeEffects` slot, holding one actor's effects in ascending application order. It is a slot
of its own beside `actorValues` for the lifetime reason `death` and `combat` are separate
slots: a current-health float is rewritten sixty times a second, while an effect list changes
only when something is applied, expires or is dispelled.

Each `ActiveEffect` carries its source (potion, ingredient, spell or enchantment, plus the
record key), the MGEF it is an application of, the applying actor where one exists, its mode,
its duration and elapsed time, and one entry per actor value it acts on. Applications are
numbered per actor rather than globally, so two applications of the same potion are genuinely
two effects and the number survives a save round trip without the save carrying an allocator.

The component is dropped entirely once it empties, so an actor whose effects all expired stops
being dirty for this slot.

## Ticking

`ActiveEffectRuntime.advance(delta:accumulator:over:)` runs whole 1/60 s steps, capped at
eight per frame, exactly as `ActorValueRuntime` regeneration does. It shares
`Renderer.onWorldUpdate` with regeneration and the Papyrus VM, so a menu-paused frame delivers
delta 0 to all three and none of them advances — the established rule.

The tick set is the player plus every resident actor, the same set regeneration advances: an
actor in a cell that is not loaded is not simulated at all in this engine.

One consequence worth stating, because it was a real bug this item fixed:
`ActorValueRuntime`'s regeneration step rewrites the whole actor-value component every frame,
and it now carries the general table through that write. Without that, a held modifier would
survive for exactly one frame.

## Condition gating

An effect entry's `CTDA` list is evaluated against the target at application time through the
same [`ConditionEvaluator`](/engine/runtime-state.md) every other site uses, with both run-ons
naming the receiving actor. An empty list is true, which is what an unconditioned entry means.
A list this engine cannot evaluate is the documented reason-tagged false and the entry is
skipped and counted — never a silent pass.

Conditions on the MGEF itself are not evaluated yet; see [Limits / next](#limits--next).

## Stacking

Two applications of the same effect are two effects and both hold their own share of the
modifier slot. Two rules override that:

- **No Recast.** "Once the magic effect is applied to a target, it cannot be cast again on the
  same target until it has worn off or been dispelled." A second application while the first
  runs is refused and counted.
- **Peak Value Modifier keywords.** "If there are two PVMs with the same keyword active at the
  same time, the one with the lower `<mag>` will be dispelled automatically?" — the question
  mark is the wiki's own. OpenSky implements the rule as written: the stronger survives, the
  weaker is dispelled, and an incoming weaker one is refused rather than displacing the
  stronger. **The uncertainty is real and is recorded here rather than hidden.**

## Consuming a potion or an ingredient

`ActiveEffectRuntime.consume` is the first consumer. It removes one unit through
[`InventoryRuntime`](/engine/runtime-state.md) and applies what the item does to the target.
The removal happens only on success, and a consume that applies nothing still costs the unit —
which is what drinking a potion of an unimplemented effect does in the original game.

ALCH applies its whole effect list. INGR applies **only its first effect**, which UESP states:

> Ingredients listed in bold have that effect as their first, meaning that eating a sample of
> that ingredient will provide a small version of that effect.

Which effects eating an ingredient *reveals* is a different question — the Alchemy skill's
Experimenter perk changes it — and that is discovery state belonging to the alchemy milestone,
not application.

Reachable two ways, both routing through the same `GameViewController.consumeMagicItem` so
they cannot diverge: the **Consume** button in
[World > Inventory Menu > Menu](/engine/inventory-menu.md), which acts on the selected row,
and the **Consume carried item** button in the panel section below, which acts on the first
ALCH or INGR the player carries.

## The AEFF save chunk

Additive and split out of `RDLT` for the same reason `AVAL` and `DETH` are. One entry per
actor carrying timed effects, each listing the effects with their remaining duration; a
session in which nothing was applied writes no chunk at all.

Per effect, in order: the sequence, the source kind, the source record key, the MGEF key, an
optional caster key, the mode, the detrimental byte, the duration, the elapsed seconds, the
seconds already paid out, an optional stacking keyword, then one `(index, magnitude, applied)`
record per actor value.

The chunk stores `elapsed` rather than "remaining" so a reloaded effect reports the same total
duration a readout showed before the save.

**This chunk is what makes `AVGN`'s dropped temporary modifier recoverable.** The general
actor-value chunk deliberately does not persist the temporary slot, because persisting both it
and the effect that established it would double every buff on reload. Each stored effect
records how much of the slot it owns, and `reestablishModifiers(on:)` rebuilds the slot from
that after a load.

Instant effects are not in the chunk and cannot be: a zero-duration effect moved an actor value
once, and the moved value is what `AVAL` and `AVGN` already carry.

Tolerance follows the container's rules. An unknown chunk is skipped by its declared length, a
degenerate effect (zero duration, no values) is normalized away by the type rather than failing
a load, and an unknown source kind or mode is the one hard stop — both are closed enumerations
this build wrote itself.

## Casting

Roadmap item 19.7, issue #470. The first half of the caster runtime: knowing spells,
readying one to a hand, and casting the **self-delivery** ones end to end. Aimed delivery,
projectiles and resistances on hit are item 19.8.

Everything below is cited or measured. The behaviour comes from two UESP pages and one
observation of the user's own install:

- **Magic Overview** for the two casting shapes, the failure when magicka is short, and the
  concentration rule (<https://en.uesp.net/wiki/Skyrim:Magic_Overview>).
- **Magicka** for the regeneration rule (<https://en.uesp.net/wiki/Skyrim:Magicka>).
- **Powers** for the once-per-day rule (<https://en.uesp.net/wiki/Skyrim:Powers>).
- **Books** and **Mod File Format/BOOK** for what reading a tome does
  (<https://en.uesp.net/wiki/Skyrim:Books>,
  <https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/BOOK>).

Where a source is silent the gap is stated rather than filled in; see
[Limits / next](#limits--next).

## The spellbook

`SpellbookState` is a [world-state component](/engine/runtime-state.md) in the `spellbook`
slot, holding one actor's known spells, the books it has read, the spell readied in each
hand, and the whole game day each greater power was last spent on.

Four things in one slot rather than four slots, and the reason is an invariant rather than
write locality: **a readied hand must name a spell the actor knows**. Forgetting a spell that
is in a hand has to clear that hand in the same write, and a save whose load order no longer
carries a readied spell has to drop the hand rather than restore it dangling. `init`
normalizes both, which is also what makes the type the `SPLB` decoder's entry point — the
same role `ActiveEffectState.init` plays for `AEFF`. Everything in the slot changes on a
player action and nothing per frame, so splitting further would buy nothing.

A known key this load order cannot resolve **stays known**. Removing a plugin must not
destroy progress; the key simply drops out of the resolved listing.

### Where spells come from

Three sources, in the order a session meets them:

1. **The two spells the player starts with.** UESP: "You will always know the spells Flames
   and Healing by the time you start Unbound, regardless of your race." The obvious data
   source would be the SPIT "PC Start Spell" flag, and **it is not the mechanism**: across
   the whole vanilla load order that bit is set on exactly one record, `PCHealRateCombat`.
   Vanilla grants Flames and Healing from the intro quest's Papyrus script, which this build
   does not run. So `SpellStore.vanillaStartSpellEditorIDs` names the two by editor ID and
   resolves them through the load order — a load order carrying neither grants nothing.
   `CasterRealDataTests` pins the finding so it cannot quietly rot.
2. **An actor's own `SPLO` run.** `NPC_` and `RACE` both carry one, now decoded
   (`ActorBase.spells`, `Race.spells`). The `SPCT` count in front of the run is deliberately
   not read: counting the entries answers the same question and cannot disagree with the
   file. A vanilla race's run is its racial ability plus its greater power — `NordRace`
   carries `RaceNord` and `PowerNordBattleCry`.
3. **Reading a spell tome.**

### Reading a tome

The cited rule is the **mark**, not the removal. UESP's Books page states the teaching rule —
"Spell Tomes: opening the book for the first time teaches you a spell" — and the BOOK format
page records the mark on the DATA flag byte: "0x08 - Read ([verification needed] not used in
static game data, flag in save game data for already read books?)". The question mark is the
wiki's own.

So `SpellbookRuntime.read` adds the taught spell and records the book in `readBooks`, and the
mark is what stops a second reading teaching again. It does **not** take the tome out of the
inventory: neither source says the book leaves it, and the mark is per reader here, because
per-reader is the only reading that survives an NPC picking the book up. Whether vanilla also
destroys the tome is recorded in [Limits / next](#limits--next) rather than guessed at.

`ItemDefinitionStore.teachesSpell` is the link: BOOK DATA's "teaches" union read under the
`0x04` flag, which `Book.swift` already decoded and nothing consumed until now.

## Readying a spell to a hand

Spells get their own component and their own equip path, and that is a deliberate departure
from the issue's first suggestion. `EquipmentRuntime.equip` refuses to equip anything the
owner does not hold, and that refusal is load-bearing — "silently equipping an item out of
nowhere is how a duplication bug hides". **A spell is never held.** It has no stack, no
weight, no `EquippableItem` entry, and it cannot be dropped, sold or given away. Widening
`equip` to accept a FormID nobody holds would remove the guard for every caller in order to
serve the one caller that legitimately needs it.

So the two layers share what they actually collide over: hands. `EquipmentOccupancy` and
`HandSlots` are the same types, and `SpellbookRuntime` arbitrates **both** directions —
readying a spell unequips the weapon or shield whose hand it takes, and `equipItem` unequips
the spell whose hand a weapon takes. That second direction is why the item path routes
through `SpellbookRuntime` rather than calling `EquipmentRuntime.equip` directly.

Which hands a spell takes comes from its `ETYP`, walked through the
[EQUP graph](/formats/magic-records.md) exactly as a weapon's is — with one distinction the
weapon path never needed. `BothHands` and `EitherHand` name the same two parents and differ
only in the DATA "use all parents" byte, so `EquipSlotHands.choice` keeps the two readings
apart:

| Reading | What it means | What readying does |
|---|---|---|
| `.fixed(hands)` | Every hand it names, at once | Fills all of them, whichever hand was asked for |
| `.choice(hands)` | One of them, the equipper picks | Fills the requested hand, or refuses when the slot does not offer it |
| `.fixed([])` | A resolved slot taking no hand — Voice, Potion | `SpellbookError.notHandEquippable` |

`hands(of:)` still gives the one deterministic answer it always did (a choose-one slot
resolves to the right hand when the right hand is an option), so nothing about weapon
occupancy moved.

Against the real load order: over 300 spells resolve to a readiable hand, and a handful do
not — `WerewolfChangeFX`, `DLC1VampireChangeFX` and the `DLC2VoiceElementalFury` run are
typed as spells but authored against Voice or nothing, because a script or a shout applies
them rather than a hand. Most greater and lesser powers resolve to no hand at all, which is
why a readied power is the documented refusal rather than a gap: a power belongs on the
shout button, and the voice slot is 19.4's stated out-of-scope note.

## The cast loop

`CasterRuntime` is a main-actor director in the shape `MeleeCombatRuntime` takes, driven from
the frame the renderer already runs, with everything it touches the world with behind
`CasterWorld` so the whole loop is testable against a fake.

One difference from melee is deliberate and is this item's known gap. Melee and archery read
their timing back out of the behavior graph — the engine raises `attackStart` and the *graph*
decides which frame contact is on. No casting graph is driven yet (M25/M26 owns the
animation), so the charge here is timed against the SPIT charge time instead. When the graph
arrives it replaces this clock the same way it replaced melee's, and the phases stay.

UESP states both casting shapes in one paragraph:

> Some spells will trigger immediately upon being cast and can be maintained as long as held.
> Others require holding to charge the spell and releasing to cast it. Casting a spell of
> either form depletes the caster's magicka based on the cost of the spell and will continue
> to do so if the spell is maintained. Attempting to cast a spell with a cost higher than
> your available magicka will result in the failure of the attempted casting.

### Fire and forget

1. `begin` resolves the readied spell, checks every refusal, and enters `charging`. A spell
   with no charge time reaches `ready` on the same call.
2. `advance` accumulates the charge until it reaches the SPIT charge time.
3. `release` checks the cost against magicka, takes it off, and hands the effect list to
   `ActiveEffectRuntime` with the caster as the target — which is what self delivery means.

Releasing inside the charge casts nothing and spends nothing.

**Magicka is checked twice**, at step 1 and again at step 3, because it can fall between them:
a charge takes half a second and something can hit the caster inside it. UESP states the rule
once; checking it at both ends is the reading that never lets a cast land unpaid.

The cost is the one [`SpellStore`](/formats/magic-records.md) already computed, so nothing
recomputes it and a manual-cost record is honoured for free.

### Concentration

`begin` reaches `concentrating` and stays there. Cost is charged **continuously**
(`cost x delta`), so the magicka bar moves smoothly rather than in one-second steps, and the
effect list is applied **once on entry and once per whole second after that**. Applying on
entry rather than a second later is what makes a maintained heal start healing when it starts
costing.

UESP: "Concentration spells do not have a set duration. Rather, the duration is determined by
how long you hold the casting trigger." The SPIT cast duration is the floor under that: a
release inside it keeps the cast running until it elapses. When the magicka runs out the cast
ends with the same insufficient-magicka refusal, taking whatever was left — the caster paid
for the fraction of a second they got.

The same arithmetic detail `ActiveEffectRuntime` documents applies here and was a real
failure the suites caught: 1/60 has no exact binary representation, so sixty steps sum to
slightly under one second. `SpellCastState.secondTolerance` is a millisecond of slack, and
without it a maintained spell would skip an application every second.

### What refuses a cast

Every refusal is a `SpellCastFailure` with a sentence, counted in `CastingTally`, and shown
verbatim on the panel. Nothing is a silent no-op.

| Refusal | Why |
|---|---|
| `noSpellReadied` | That hand holds no spell |
| `unknownSpell` | A readied key this load order no longer carries |
| `notCharged` | Released before the SPIT charge time elapsed |
| `insufficientMagicka` | The cited rule, at begin, at release, and mid-concentration |
| `deliveryUnsupported` | Anything but self delivery — 19.8's ground, counted rather than pretended |
| `abilityNotCastable` | An ability is carried, not cast |
| `powerAlreadyUsedToday` | The cited once-per-day rule |

### Regeneration stands down

UESP: "Magicka will not regenerate while you are casting a spell." The player is dropped from
the regeneration set entirely while either hand is mid-cast, rather than having magicka
regeneration suppressed on its own. That is a **stated deviation**: the same paragraph names
no other value, and no source says health and stamina keep going, so the wider reading is
recorded here rather than hidden.

## Abilities and powers

An **ability** is a spell of SPIT type `ability`: nothing casts it, the actor simply has it,
and `CasterRuntime.begin` refuses one from a hand. `applyAbilities` applies every ability the
actor knows through the effect runtime.

Vanilla authors most ability entries with a **zero duration**, meaning "for as long as the
actor carries it", and the active-effect runtime has no permanent mode — a zero-duration
entry there applies once and is stored nowhere. For a resistance that would be a one-off
nudge wearing the name of a permanent bonus, so those entries are **counted and not applied**
(`CastingTally.unheldAbilityEntries`); the timed ones apply normally. Applying nothing is the
honest answer where applying something would be wrong.

A **greater power** is once per game day. `SpellbookState.powerDays` records the whole
`GameClock.daysPassed` each power was last spent on, and a second cast on the same day is the
documented refusal. Lesser powers are unrestricted, which is what UESP states: "Unlike
Greater Powers, each Lesser Power can be used an unlimited number of times per day."

## Cast input and the animation seam

No new binding. The same two buttons melee and archery already use, routed by what the hand
holds — exactly the rule `ArcheryIntent` states for the bow, that it is the same button and a
drawn bow takes the attack press away from the swing:

- A spell readied in the **right** hand takes the attack button.
- A spell readied in the **left** hand takes the block button.
- A hand holding no spell leaves its button to melee.

`CastingIntent` carries the held levels and `CasterRuntime.acceptFrame` turns them into
begin/release **edges**, so a held button does not restart the charge sixty times a second.
Unequipping mid-cast cancels the charge rather than leaving one nothing can release.

The state seam this item owes the animation layer is `CombatHandType.spell` (9), the value
`magicbehavior.hkx` reads. `equippedHands()` lays a readied spell over either hand, so the
graph is told a spell is out even though no casting clip plays yet — the state is queryable
and the miss is tallied rather than invisible, which is the boundary with M25/M26.

## The SPLB save chunk

Additive and split out of `RDLT` for the same reason `AEFF` is. One entry per actor that
knows a spell, has read a book, or has spent a greater power; a session in which nobody
learned anything writes no chunk at all.

Per actor, in order: the key, the cell, the known-spell list, the read-book list, the two
readied hands each behind a presence byte, and the spent-power list as `(power, whole game
day)` pairs. Every list is in the component's own ascending key order, so re-encoding an
unchanged spellbook produces identical bytes.

**Readied hands travel here and casts do not.** A readied spell is a loadout the player chose
and has to survive a reload; a charge in progress is frame state, and restoring one would put
the player back mid-cast with magicka already committed.

Nothing rejects a spellbook on content. A duplicate key, a hand naming a spell the known list
does not carry, and a spent-power entry for a forgotten spell are all normalized away by
`SpellbookState.init` rather than failing a load. There is no hard stop of the kind `AEFF`
has, because this chunk carries no closed enumeration: every field is a key, a count or a
signed day.

## Delivery: casting at something else

Roadmap item 19.8, issue #471. The second half of the caster runtime: spells that
leave the caster. The delivery vocabulary is the record's own, decoded from
MGEF DATA and SPIT — 0 Self, 1 Touch, 2 Aimed, 3 Target Actor, 4 Target Location
(<https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/MGEF>) — and UESP's Magic
Overview describes the shapes those numbers stand for:

> Spells that don't target the one using them vary in range: some only work on
> touch, several are fired as projectiles, some are maintained as a short-ranged
> spray, and a few (primarily Master level spells) affect everything within a
> certain distance of the caster.
> (<https://en.uesp.net/wiki/Skyrim:Magic_Overview>)

What this build carries out, and what it counts:

| Delivery | Fire and forget | Concentration |
|---|---|---|
| Self | applies to the caster | applies to the caster once a second |
| Aimed | fires the MGEF's PROJ | applies to whatever the aim ray reaches, once a second |
| Target Actor | applies to the aimed actor, within SPIT range | counted |
| Touch | counted | counted |
| Target Location | counted | counted |

**Touch and Target Location are refused and counted rather than approximated, and
the reason differs.** Touch needs the melee-reach geometry and the contact frame
the animation graph owns (M25/M26); approximating it as a zero-range aimed cast
would land a "touch" spell at the far end of a room. Target Location places an
effect on the ground, which in vanilla is an EXPL or a rune placement — the EXPL
runtime is explicitly out of this item's scope and is M26, so there is nowhere for
the effect to live. Every refusal is the same `deliveryUnsupported` failure with a
sentence and a tally entry the panel prints.

Against the user's own load order, the census is 1452 SPEL records: 733 self, 451
aimed, 155 touch, 74 target location, 39 target actor — so 1218 of them, 84%,
resolve to a delivery this build runs (2026-08-17,
`SpellDeliveryRealDataTests.theDeliveryCensusIsWrittenForTheRecord`, written to
gitignored `logs/spell-delivery/`).

The payload a delivery carries away is resolved **once, at cast time**, and never
re-derived: the spell key, its plugin, the caster, the whole effect list, whether
any entry is hostile, the SPEL "Ignore Resistance" flag, and the PROJ its MGEF
names. That is the same rule a bow's damage already followed — a projectile in
the air has to apply the spell that was cast, not whatever the caster has readied
by the time it lands.

## Spell projectiles

There is one projectile pipeline, not two. An aimed fire-and-forget cast fires the
PROJ its MGEF names through the same `ProjectileRuntime` an arrow flies through,
so it obeys the same fixed step, the same closed-form integrator, the same impact
query, and the same range and lifetime bounds. `ProjectileShot` carries a payload
that is either an arrow or a spell, and every arrow-only behaviour — spending
ammunition, sticking in the surface, the draw-scaled launch speed, the archery
tilt-up angle — is conditional on that payload.
[Archery](/engine/archery.md#one-shot-model-two-payloads) has the table.

The PROJ resolves through the same `ItemDefinitionStore` index the arrow path
reads, by the FormID the MGEF carries rather than through an AMMO. A spell whose
MGEF names no PROJ, or whose PROJ this load order does not carry, or whose PROJ is
hitscan or has no launch speed, launches nothing — and that is a counted refusal
rather than a projectile standing still in the caster's face.

Concentration aimed casting — the flamethrower shape — fires nothing. It reuses
the aim ray and applies to whatever that ray reaches, on the cadence
`CasterRuntime` already runs for a maintained self cast: once on entry and once
per whole second held. The ray is **resampled on every application**, so sweeping
a beam off a target stops applying to it while the cast keeps running and keeps
costing.

## What a landed spell reaches

The struck actor first, as the **direct** target, which receives every entry.
Then every actor inside the widest area the payload carries, as **bystanders**,
each receiving only the entries whose own area reaches it. That split is what
vanilla `Fireball` is authored for: an area damage entry beside a point stagger
entry, so the blast damages everything nearby and staggers only what it struck.
The caster is never caught by its own spell, matched on key for the reason a shot
never hits its own shooter. Bystanders are ordered by distance and then by key, so
two actors at the same remove are always applied to in the same order.

Distance is measured to the actor's **capsule**, not to its feet, so a blast at
head height catches somebody standing beside it.

**EFIT's area is authored in feet.** That is measured, not assumed: the resolved
game-setting table names the effect item's area unit outright
(`sMagicEffectItemFeet`), and vanilla `Fireball` carries an EFIT area of 15
against UESP's description of the same spell as "a fiery explosion for 40 points
of damage in a 15 foot radius" (<https://en.uesp.net/wiki/Skyrim:Fireball>;
probed 2026-08-16 with `openskycli record Fireball`, pinned by
`SpellDeliveryRealDataTests`).

**How many world units a foot is, is not settled by any source this session could
reach**, and that uncertainty is stated rather than hidden.
`MagicAreaSettings.documentedDefaults` carries 128/6 units per foot, derived from
this engine's own `PlayerCapsule.standard` height of 128 units for an adult
human. It is a setting rather than a constant so the number can be corrected
without touching the rule; see [Limits / next](#limits--next).

A projectile that struck geometry still applies its **area** entries to whoever
was standing by the wall. One whose entries are all point effects reaches nobody,
which is what an area of zero against a wall means.

## Resistances on hit

Only **hostile** effects scale. UESP states the rule over damage rather than over
every effect — "Magic Resistance decreases the damage of any offensive spell by
the displayed percentage" (<https://en.uesp.net/wiki/Skyrim:Magic_Overview>) —
and the MGEF Hostile flag is the record's own word for "offensive". A restore or
a fortify reaches the effect runtime unscaled, so a healing spell is not resisted.

The multiplier is item 19.5's `magicDamageMultiplier`, called rather than copied:
Resist Magic first, then the MGEF's own resistance actor value, multiplicatively,
with the 85% cap applying to the player alone
([actor values](/engine/actor-values.md#resistances)). A **weakness** is the same
formula with a negative resistance and needed one change there: the fraction no
longer clamps at zero, so -30 points reads -0.3 and multiplies damage by 1.3.

The SPEL flag xEdit names "Ignore Resistance" skips the whole step, which is why
the payload carries it rather than the resolver assuming every spell is
resistible.

Every scaled entry produces a `SpellMagnitudeAdjustment` naming the effect, the
target, the resistance actor value, the base magnitude and the multiplier. That is
deliberate and is the item's evidence: **a health bar moving is not proof that the
multiplier was the documented one**, so the adjustment is printed on the panel and
asserted in the suites.

## Combat consequences

A landed spell reports itself to the combat loop exactly as an arrow does, through
`notePlayerHits` — the target is provoked, put in the fight, and staggered.
Death handling is unchanged: the effect runtime moves health through
`ActorValueRuntime`, and `ActorDeathComponent` answers when it reaches zero.

The one difference is the filter. `ProjectileTrace.provokes` is what the loop
reads, and it is true for every arrow and only for a spell whose effects are
hostile — healing a follower at range must not start a fight with them. A
projectile that expired in the air provokes nobody, because it reached nobody.

A spell hit also raises `OnHit` on the target's scripts, with the PROJ named.
`akSource` is left `None` rather than filled with the spell: the event carries a
`FormID` and a cast spell is addressed by `ReferenceKey`, which is a load-order
identity a raw FormID cannot round-trip.

## Verification

Sidebar path **World > Combat & Physics > Magic Effects**
(`Destination-combatPhysics`, `PanelSection-combatMagicEffects`). Controls:
`MagicEffectConsumeControl`, `MagicEffectDispelControl`. Readout:
`CombatMagicEffectsStatsLabel`. It sits beside Actor Values because that is what it acts on: a
potion that restored health is only convincing next to the health it restored.

The inventory menu's own action is `InventoryMenuConsumeControl` under
**World > Inventory Menu > Menu**.

Covering tests:

- `MagicEffectPlannerTests` — archetype dispatch, the dual-value weight, the Recover mode
  split, the Peak Value Modifier keyword, and each skip reason.
- `ActiveEffectRuntimeTests` — instant restore and damage, the held modifier and its exact
  reversal, per-second pay-out, condition-gated skip, both stacking rules, dispel,
  `HasMagicEffect`, modifier re-establishment after a load, and that regeneration does not drop
  a held modifier.
- `MagicItemConsumptionTests` — drinking a potion through `InventoryRuntime`, the ingredient
  first-effect rule, and the two refusals.
- `ActiveEffectSaveTests` — the round trip, the modifiers a restored effect owns, no chunk for
  a session with no effects, and the unknown-source-kind hard stop.
- `CombatMagicEffectsPanelTests` — accessibility ids, control routing, and the readout with and
  without a runtime.

Casting has its own path: **World > Combat & Physics > Spellcasting**
(`Destination-combatPhysics`, `PanelSection-combatSpellcasting`), directly below Magic
Effects because that is where a cast lands — the acceptance picture is a healing spell moving
the magicka meter down and the health meter up, and the three readouts are read together.
Controls: `SpellcastingLearnControl`, `SpellcastingReadTomeControl`,
`SpellcastingSelectControl`, `SpellcastingReadyRightControl`, `SpellcastingReadyLeftControl`,
`SpellcastingCastRightControl`, `SpellcastingCastLeftControl`. Readout:
`CombatSpellcastingStatsLabel`.

The Cast buttons run one whole cast without holding a button — the charge is fast-forwarded,
then the cast is released — so the behaviour is verifiable from the panel alone. The
held-button path in walk mode reaches the same states over real frames.

Covering tests:

- `SpellbookRuntimeTests` — learning, forgetting, the start-spell lookup, an actor's `SPLO`
  run, the tome rule and its second reading, hand occupancy for one- and two-handed spells,
  the Voice refusal, and the readied-hand invariant a forget enforces.
- `CasterRuntimeTests` — the whole fire-and-forget cast, an instant-charge spell, the
  early-release refusal, insufficient magicka at both ends, unsupported delivery, the
  concentration drain and cadence, the minimum cast duration, the once-per-day power, the
  ability entries that carry no duration, and the button edges.
- `SpellbookSaveTests` — the `SPLB` round trip, no chunk for a session that learned nothing,
  the readied-hand invariant across a load, and a spellbook-only actor's own entry.
- `EquipSlotTests` — the all-of/one-of distinction and the occupancy a named hand request
  gets.
- `CombatSpellcastingPanelTests` — accessibility ids, the seven controls' routing, and the
  readout with and without a runtime.
- `CasterRealDataTests` (env-gated) — where start spells actually come from, a race's `SPLO`
  run, the SPIT shapes of `FastHealing` and `Healing`, and how many vanilla spells and powers
  the EQUP walk can put in a hand.
- `CasterAcceptanceRealDataTests` (env-gated) — the whole chain against the user's install,
  headless: find the tome by its `DATA` link rather than by name, read it, ready the spell it
  teaches, cast it, and check that magicka fell by the computed cost and health rose. It
  leaves a one-line summary in gitignored `logs/caster-acceptance/`.

Aimed delivery adds one line to the same panel rather than a destination of its
own, because it is read together with the cost and the magicka above it:
`CombatSpellcastingStatsLabel` now prints how many projectiles left the caster,
the census of deliveries cast, and — for the most recent landed spell — one line
per hostile entry spelling `effect on target: base x multiplier = adjusted`. That
line is the resistance rule's verification surface.

Covering tests for item 19.8:

- `SpellHitTests` — the resistance arithmetic against synthetic resist values (a
  plain fraction, the Resist Magic composition, a weakness above 1, an immune NPC,
  the player's 85% cap), the unscaled restorative, the "Ignore Resistance" flag,
  the area rule by distance, the feet-to-units conversion, bystander ordering, and
  a target with no holder.
- `CasterDeliveryTests` — the aimed cast that fires instead of applying, the
  payload resolved at cast time, the launch that could not happen, target-actor
  delivery within SPIT range, aiming at nobody, the aimed concentration cadence
  over synthetic time, sweeping the beam off a target, the delivery support
  matrix, and the PROJ profile the MGEF names.
- `ProjectileSpellTests` — a spell projectile on its own PROJ numbers with no
  ammunition and no tilt, an arrow that still takes the tilt, nothing sticking,
  the direct target, the area bystander, a point spell against a wall, an area
  spell against a wall, and what does and does not provoke.
- `CombatSpellcastingPanelTests` — the delivery readout, with and without a
  landed spell.
- `SpellDeliveryRealDataTests` (env-gated) — the whole MGEF-to-PROJ chain for a
  pinned vanilla destruction spell, sane trajectory numbers out of it, the
  resistance actor value a vanilla fire effect names, the `Fireball` area
  measurement, and the delivery census written to gitignored
  `logs/spell-delivery/`.
- `SpellDeliveryAcceptanceRealDataTests` (env-gated) — the whole chain against the
  user's install, headless: ready vanilla `Firebolt`, cast it at an actor carrying
  40% `Resist Fire`, fly the projectile on the record's own numbers, and check
  that the health taken off is the adjusted magnitude rather than the authored one
  and that the hit provokes. It leaves a summary in gitignored
  `logs/spell-delivery-acceptance/`. On the local install that run reads: 41
  magicka spent, 583 units of flight in 0.23 s, `FireDamageFFAimed` 25.0 x 0.6 =
  15.0, target health 500 -> 485, provokes true.

The existing archery suites — `ProjectileRuntimeTests`, `ArcheryRuntimeTests`,
`ProjectileStuckArrowTests`, `M15AcceptanceChain` — are unchanged in behaviour and
stay green, which is what makes "one shot model" a claim rather than a hope.

The 19.7 acceptance record, in the format
[the convention](/tools/sidebar-acceptance.md) defines:

```text
Milestone: M19.7
Sidebar path: World > Combat & Physics > Spellcasting
Destination id: Destination-combatPhysics
Controls exercised: SpellcastingLearnControl, SpellcastingReadTomeControl,
  SpellcastingSelectControl, SpellcastingReadyRightControl, SpellcastingReadyLeftControl,
  SpellcastingCastRightControl, SpellcastingCastLeftControl
Readout: CombatSpellcastingStatsLabel
Deterministic tests: CombatSpellcastingPanelTests, CombatPhysicsPanelTests,
  SpellbookRuntimeTests, CasterRuntimeTests, SpellbookSaveTests, CasterRealDataTests,
  CasterAcceptanceRealDataTests
Local A/B (optional, never committed): logs/caster-acceptance/acceptance.txt
```

## Limits / next

- **Touch and target-location delivery do not cast.** Both are the documented
  `deliveryUnsupported` refusal and a tally entry; see
  [Delivery](#delivery-casting-at-something-else) for why each is counted rather
  than approximated. Target-actor concentration is refused for the same reason:
  holding a beam on a named actor needs the AI targeting issue 19.10 owns.
- **How many world units a foot is, is a stated assumption.** The EFIT area unit
  is measured (feet); the conversion into world units is derived from this
  engine's own player capsule and is a setting, not a constant. Settling it needs
  an observation of the running game — cast `Fireball` between two actors a known
  distance apart and find the distance at which the second stops taking damage.
- **EXPL explosions are not run.** A PROJ's explosion link is decoded and left
  alone, so a vanilla area spell's blast reaches actors through its EFIT area
  rather than through the explosion the original game detonates. Visual and audio
  effects are M26.
- **Wards, spell absorption and reflect are not implemented.** UESP states that
  "Spell Absorption is calculated before Magic Resistance"
  (<https://en.uesp.net/wiki/Skyrim:Magic_Overview>), so the order is known and
  the runtime is not; the SPEL "Disallow Absorb/Reflect" flag is decoded and
  unread.
- **A spell projectile is invisible.** It flies, it hits and it applies, but
  nothing draws the PROJ's model or its muzzle flash and no impact art plays —
  M26 owns all three. The trajectory is inspectable through the Archery panel's
  own trace in the meantime.
- **There is no aim assist.** Vanilla nudges a cast toward a target; this build
  aims exactly where the camera points, because nothing models the assist for an
  arrow either.
- **Whether a spell tome leaves the inventory is not implemented**, because neither cited
  source says it does. UESP documents the "Read" mark and hedges it with its own
  `[verification needed]`; nothing states the removal. The mark is implemented and the
  removal is not, and confirming it needs an observation of the running game that this
  session could not make.
- **A zero-duration ability entry is counted, not held.** It needs a permanent mode the
  active-effect runtime does not have; see [Abilities and powers](#abilities-and-powers).
- **Dual casting is not implemented.** UESP documents the perk and the 2.2x-effect-for-2.8x-cost
  formula, but the perk system is M20, so two hands casting the same spell is two casts.
- **The voice slot is not modelled**, so a greater power cannot actually be readied anywhere;
  the once-per-day rule is implemented and reachable, and 19.4's out-of-scope note owns the
  slot itself.
- **Casting animations, hand effects and sounds** are M25/M26. `CombatHandType.spell` is the
  seam this item leaves them.
- **The spells menu and favorites** are the in-game UI's; the sidebar panel is this
  milestone's inspection surface (19.12).
- **Enchantment triggers** are issue 19.9.
- **Tapering is not applied.** The Creation Kit documents the taper weight, curve and duration
  formula, but no vanilla potion or ingredient effect this item consumes uses it, so
  implementing it here would be untested ground.
- **MGEF-side conditions are not evaluated**, only the effect entry's own list. The Creation
  Kit distinguishes the two and the distinction matters for concentration spells, which is
  casting's problem.
- **A timed Recover effect on a primary is counted, not applied.** It needs the
  base-plus-modifiers storage for health, magicka and stamina that item 19.5 declined to build;
  see [actor values](/engine/actor-values.md).
- **`HasMagicEffect` is answerable but not registered.** The component answers the query;
  registering the condition function and the Papyrus native is issue 19.11.
- **Visuals and sounds** for effects are milestone M26. The ALCH consume sound is decoded and
  carried through `MagicItemUse` for the milestone that plays it.

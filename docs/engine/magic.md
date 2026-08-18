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
timestamp: 2026-08-18T00:00:00Z
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
- [AI spell use](#ai-spell-use)
- [Item enchantments](#item-enchantments)
- [The script-facing surface](#the-script-facing-surface)
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
| Cast loop | `opensky/Engine/Magic/CasterRuntime.swift`, `CasterRuntimeInput.swift` and `CasterRuntimeConcentration.swift` | app + CLI |
| Cast coverage tally | `opensky/Engine/Magic/CastingTally.swift` | app + CLI |
| Spellbook save chunk | `opensky/Engine/Formats/Save/OpenSkySave{Encoder,Decoder}Spellbook.swift` | app + CLI |
| Casting panel seam | `opensky/Engine/CastingControlProviding.swift` and `CastingControlReadout.swift` | app + CLI |
| Casting session wiring | `opensky/App/GameViewControllerCasting.swift` and `GameViewControllerCastingPanel.swift` | app |
| Casting verification surface | `opensky/App/Shell/Sections/CombatSpellcastingSection.swift` | app |
| Delivery routing | `opensky/Engine/Magic/CasterRuntimeDelivery.swift` | app + CLI |
| Landed-spell model and application | `opensky/Engine/Magic/SpellHit.swift` | app + CLI |
| Generalized shot | `opensky/Engine/Combat/ProjectileShot.swift` | app + CLI |
| Delivery session wiring | `opensky/App/GameViewControllerSpellDelivery.swift` | app |
| Enchantment charge model | `opensky/Engine/Magic/EnchantmentCharge.swift` | app + CLI |
| Enchanted-item component | `opensky/Engine/Magic/EnchantedItemComponent.swift` | app + CLI |
| Enchanted-item ledger | `opensky/Engine/Magic/EnchantmentLedger.swift` | app + CLI |
| Resolved item enchantment | `opensky/Engine/Magic/ItemEnchantmentProfile.swift` | app + CLI |
| Enchanted hit and its seam | `opensky/Engine/Magic/WeaponEnchantmentHit.swift` | app + CLI |
| Worn-effect reconcile | `opensky/Engine/Magic/WornEnchantmentApplication.swift` | app + CLI |
| Fortify terms | `opensky/Engine/Combat/CombatFortifyBonus.swift` | app + CLI |
| Enchanted-item save chunk | `opensky/Engine/Formats/Save/OpenSkySave{Encoder,Decoder}EnchantedItems.swift` | app + CLI |
| Enchantment session wiring | `opensky/App/GameViewControllerEnchantments.swift` | app |
| Actor spell baseline | `opensky/Engine/Magic/ActorSpellBaseline.swift` | app + CLI |
| AI casting session wiring | `opensky/App/GameViewControllerCombatCasting.swift` | app |
| Magic condition seam | `opensky/Engine/Magic/MagicConditionResolution.swift` | app + CLI |
| Magic condition functions | `opensky/Engine/World/ConditionFunctionsMagic.swift` | app + CLI |
| Direct function probe | `opensky/Engine/World/ConditionProbe.swift` | app + CLI |
| Spell natives | `opensky/Engine/Papyrus/PapyrusNativeSpell.swift` | app + CLI |
| Spell native bridge | `opensky/Engine/Papyrus/PapyrusWorldMagicBridge.swift` and `PapyrusWorldStateBridgeMagic.swift` | app + CLI |
| Magic condition session wiring | `opensky/App/GameViewControllerMagicConditions.swift` and `GameViewControllerMagicConditionProbe.swift` | app |

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

Since issue #472 the load path actually calls it, for the **player only**:
`loadWorldState(slot:)` re-establishes the player's slots after the snapshot is
restored, because a worn enchantment's fortify has to survive a reload and a session
that skipped the step would list the effect and show none of its bonus. No other
actor has a resolvable holder at that moment — the cells have not streamed back in —
so an NPC carrying a timed effect across a load is a stated gap rather than a
silently handled case.

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

## AI spell use

Roadmap item 19.10, issue #473. An NPC that owns spells casts them in a fight.
The decision layer is the [combat behavior machine](/engine/combat.md#the-behavior-machine);
everything below is what stands behind it.

**The NPC path is the player's path.** A fighting actor's spell is readied
through `SpellbookRuntime.equip`, begun through `CasterRuntime.begin`, charged by
`CasterRuntime.advance` and let go through `CasterRuntime.release` — the four
calls the panel's Cast button makes for the player. That is why `CasterRuntime`
keys its in-flight casts by `CastSlot` (the actor *and* the hand) rather than by
hand alone: two actors charging at once are two casts, and a hand-keyed table
would have the second overwrite the first.

An NPC casts with its right hand, always. Vanilla NPCs dual-cast and hold a spell
in either hand; picking one hand is a stated simplification.

### Where an NPC's spells come from

`ActorSpellBaselineResolver` reads them back out of records, sitting beside
`SpellbookRuntime` exactly as `InventoryBaselineResolver` sits beside
`InventoryRuntime`:

| Source | Field | Inherits through |
|---|---|---|
| The NPC_ | `SPLO` run | ACBS `Use Spell List`, so a record delegates its list upward only while that bit is set |
| The RACE the actor is | `SPLO` run | `useTraits`, because the race an actor *is* is the traits race |

**An entry may name a leveled spell list, and for a vanilla caster the
interesting ones do.** Observed against `Skyrim.esm` rather than assumed:
`LvlBanditWizard` carries seven `SPLO` entries, and every one that resolves to a
SPEL is a self buff or a heal — Ironflesh, a ward, two heals, a racial ability
and a Breton power. Its *attack* spells sit behind two `LVSP` records,
`LSpellBandit03FireFrostShock` and `LSpellBandit05FireFrostShock`, each holding
three alternatives at level 1. Without expanding those, a vanilla caster knows
nothing it could ever throw at anybody. The entry chosen is
`LeveledList.deterministicEntry` — highest level, first among ties — the same
policy the TPLT chain applies to an LVLN hop and the outfit chain to an LVLI hop.
`ActorSpellBaselineRealDataTests` pins that actor and its expansion.

The list is granted into the actor's `SpellbookState` the first time the combat
loop asks what that actor can cast, and its abilities are applied in the same
pass through the 19.7 ability path. Lazily rather than at cell build, because a
cell of forty townsfolk who will never fight would otherwise write forty
spellbook components into the save to say what their base records already say.
The grant is idempotent.

### Which of them become options

A known spell reaches the decision layer as a `CombatSpellOption` only if it
passes four gates, each refusing a different thing:

| Gate | Refuses |
|---|---|
| `spellType == .spell` | an ability, which is carried rather than cast, and a power, which is a once-a-day resource this layer has no rule for |
| delivery is not `self` | a self buff or heal, which is not something to throw at somebody |
| some effect entry is flagged hostile | a heal or a buff cast at an enemy, which nobody could read |
| the delivery is one this build carries out, and the ETYP takes a hand | a cast that was always going to be counted as unimplemented, and a spell with no hand to cast it from |

The option carries the cost, the resolved range (SPIT's, or the session's own
aimed ceiling for a record that bounds nothing), the charge time and whether it
is a concentration spell — the numbers the machine's affordability and range
gates read. The machine never reads a record.

### What a released cast does

Exactly what the player's does. A fire-and-forget aimed spell fires the MGEF's
PROJ through the archery pipeline; a target-actor spell applies to whatever the
caster's aim ray reaches; a concentration spell is held for
`CombatBehaviorSettings.concentrationSeconds` and applies once a second while it
runs. The only thing that differs is *whose* ray it is: `ProjectileRuntime.fire`
takes a `ProjectileShooter`, so an NPC's spell leaves the NPC's own eye aimed at
the middle of the player's capsule, and `CasterWorld.aimedSpellTarget` takes the
caster for the same reason.

A cast in flight is dropped rather than left running whenever the fight takes it
away — a stagger, a retreat, a lost target, a stopped fight, a death, or the
panel switch being turned off. A maintained cast whose SPIT minimum duration has
not elapsed is dropped too: the player's release is deferred until the floor is
reached because their button is still held, and an NPC has no button.

### Verified against the install

`AICastingAcceptanceRealDataTests` drives the whole chain over the load order's
own records: `LvlBanditWizard`'s nine known spells become two castable options
(Ice Spike at 48 magicka, Ice Storm at 144, both aimed and reaching 4,000
units), the machine chooses the costlier one it can afford, four casts run over
six simulated seconds, and the player loses 145 health while the caster's
magicka falls to 20. `ActorSpellBaselineRealDataTests` pins the list that fed
it. Both write a summary into gitignored `logs/`.

### Simplified on purpose

Stated as choices rather than presented as observed behaviour:

- **Combat style (CSTY) is not decoded.** Vanilla tunes when a caster prefers
  magic, at what ranges and with what magicka gating through CSTY and GMSTs; this
  build uses one probability and one selection rule, both
  [OpenSky's own numbers](/engine/combat.md#the-numbers-all-of-them-ours).
- **The strongest affordable spell wins.** Cost stands in for strength because no
  record ranks a caster's spells.
- **No shouts, no summons, no reanimation, and no self-healing mid-fight.** An
  NPC only ever casts a hostile spell at its target; the buffs and heals in its
  own list are known and never chosen.

## Item enchantments

Roadmap item 19.9, issue #472. The loop the M15 damage formulas left open: a weapon's
enchantment fires on whatever it hits and pays charge for it, a worn item's enchantment
grants its effects while it is worn, and a fortify effect from either source moves a
damage number.

### Which shape a record has, measured

The Creation Kit wiki states the authoring rules
(<https://ck.uesp.net/wiki/Enchantment>): "Armor Enchantments must use the 'Constant
Effect' casting type" and "can only have 'Self' as their delivery type"; weapons "can only
have 'Contact'"; staves "can only use 'Aimed' or 'Target Location'". Counted across this
machine's whole active load order on 2026-08-17:

| Reached from | Shape | Count |
|---|---|---|
| `ARMO` `EITM` | enchantment / constant effect / self | 2,885 |
| `WEAP` `EITM` | enchantment / fire and forget / touch | 2,939 |
| `WEAP` `EITM` | staff enchantment / aimed, target actor or target location | 86 |

So the **casting type** selects the runtime behaviour, not the record family:
`ItemEnchantmentProfile.isWorn` is a constant effect, `isContact` is a weapon's, and
`isStaff` is neither. `EnchantmentRuntimeRealDataTests` asserts every enchanted item in the
load order falls into one of the three, so an unexpected shape is a failing count rather
than a silently skipped item.

### The charge model

Two numbers, both already decoded, and no formula invented here:

- The fully charged value is the weapon's own `EAMT`, which `ItemEnchantment.charge`
  carries. `ARMO` has no such field, consistent with a worn enchantment spending nothing.
- One use costs the enchantment's own cost — the authored `ENIT` value under the
  manual-cost flag, and [`SpellCost`](/formats/magic-records.md)'s auto-calculated total
  otherwise, which `ResolvedEnchantment.cost` already resolves.

So the number of uses is `floor(EAMT / cost)`, and that was measured rather than assumed.
UESP's "Skyrim:Generic Magic Weapons" prints a "Charge/Cost = Uses" column for every
randomly generated magic weapon and states its numbers are "base values, equivalent to the
values for a player with 0 in all skills"
(<https://en.uesp.net/wiki/Skyrim:Generic_Magic_Weapons>). Five rows checked against the
install on 2026-08-17, all three numbers agreeing on every one:

| Weapon | Charge | Cost | Uses |
|---|---|---|---|
| Dwarven Warhammer of Absorption | 1000 | 18 | 55 |
| Ebony Battleaxe of the Vampire | 3000 | 109 | 27 |
| Iron Battleaxe of Dismay | 500 | 7 | 71 |
| Imperial Bow of Cowardice | 300 | 11 | 27 |
| Elven Battleaxe of Banishing | 2000 | 138 | 14 |

A weapon holding less than one whole use cannot fire and the remainder is stranded, not
spent: vanilla's enchanting menu refuses a soul gem too small to buy "at least one charge"
(<https://en.uesp.net/wiki/Skyrim:Enchanting>), so a fraction of a use is not a use. That is
also why `usesRemaining` floors. An enchantment whose cost is zero is unmetered: it fires
forever and writes no charge at all, so a cost-free weapon does not make its owner dirty on
every swing.

The charge is spent **before** the effects are applied and only once. A hit that cannot pay
applies nothing; a hit that can pay has paid even if every one of its entries turns out to
be an archetype this engine does not implement. That is the order vanilla's own readout
implies — the meter moves on the swing, not on the effect — and it keeps a weapon carrying
an unimplemented enchantment from firing forever.

### Where the charge is stored, and what that costs

`EnchantedItemState` is a [world-state component](/engine/runtime-state.md) on the owner,
holding a remaining charge per item and the effects each worn item established. It travels
in its own `ECHG` save chunk.

Charge is a *per-instance* quantity, and this engine has no per-instance item identity yet:
`ItemDefinition.stackKey` is the base FormID, and `ItemDefinitionStore`'s own header already
records that charge level is one of the facts that will make the key compound. So the key
here is the base FormID too, and the consequence is stated rather than hidden: **one owner
holding two of the same enchanted weapon shares one charge between them.** Everything
addresses an item through `charge(of:)` and `setting(charge:of:)`, so the day a stack key
becomes compound only those signatures change.

### A landed hit

A contact enchantment applies through `SpellHitApplication`, not beside it. Once an actor
has been struck, a contact enchantment and a [landed spell](#resistances-on-hit) do the same
thing — scale each hostile entry by that actor's resistances and hand the list to the effect
runtime — so item 19.8's implementation is the one implementation. The only thing added is
the charge.

Resistances therefore apply to a weapon enchantment. `ENIT` carries no "ignore resistance"
flag of the kind `SPIT` has (its two documented bits are the manual-cost switch and
extend-duration-on-recast), so there is no record-level way to bypass the step and none is
invented.

Both combat runtimes reach it through one seam. `WeaponEnchantmentApplying` is refined by
`MeleeCombatWorld` and `ProjectileWorld` alike, so a swing and an arrow take the same path,
exactly as `reportScriptHit` is implemented once for melee, archery and the combat loop. The
weapon's resolved enchantment rides with the swing profile and with `ArrowPayload`, fixed
when the swing or the shot started — an arrow in the air applies the enchantment the bow
that fired it was carrying, not whatever is equipped when it lands.

### A worn item

A constant effect is not a timer, so `ActiveEffectMode` grew a third case. `.constant` holds
its magnitude in the temporary modifier slot exactly as `.modifier` does and nothing ever
takes it back on its own: 618 of the 620 effect entries behind vanilla's constant-effect
enchantments author an EFIT duration of zero, so reading that zero as "apply once" would
have been wrong. `ActiveEffect.isExpired` is false for a constant effect, ticking leaves it
alone, and `ActiveEffectState` keeps it despite its duration.

Applying and removing is written as a **reconcile** rather than an equip hook. The engine
equips from several places — the inventory menu, the Items panel, a load — and hanging
"apply the enchantment" off each of them would be one missed call away from an effect that
never comes off. `WornEnchantmentApplication.reconcile(worn:on:using:)` takes who is wearing
what and makes the stored constant effects match; calling it twice changes nothing, and every
equip path calls it afterwards.

Removal is exact because the applied `ActiveEffect.sequence` numbers are recorded per item. A
helmet and a necklace can carry the *same* ENCH — vanilla robes and circlets do — so
dispelling by source record would take off effects the other item granted.

Worn effects are applied unscaled: resistances are for a hostile magnitude arriving from
outside, and a worn item's enchantment is applied to its own wearer.

### The worn restriction gates nothing at runtime

`ENIT`'s worn-restriction link is a form list of keywords, and the same Creation Kit page
describes it as an *authoring* restriction: "When the player tries to enchant a Weapon or
piece of Armor with this Enchantment, only items that have one of the keywords in this list
may be enchanted with it."

It is exposed as a question — `ItemEnchantmentProfile.allowsWearing(keywords:listedKeywords:)`
— and deliberately not consulted when a worn item's effects are applied, because enforcing it
would break vanilla items. Of the 2,727 enchanted `ARMO` records whose enchantment chain
names a restriction list, **70 carry no keyword their own list names** (measured 2026-08-17)
— among them the Gauldur Amulet and its three fragments, a Dragon Priest mask, and Cicero's
hat. `EnchantmentRuntimeRealDataTests` pins those counterexamples so nothing can quietly
start enforcing the list.

### Fortify effects in the damage formulas

UESP notes that "Many Fortify Skill enchantments actually affect the action directly instead
of increasing your skill" (<https://en.uesp.net/wiki/Skyrim:Enchanting_Effects>), and the
records say which value each one moves. Read off the install on 2026-08-17, every one a Peak
Value Modifier with the Recover flag set:

| MGEF | Actor value | Index |
|---|---|---|
| `EnchFortifyOneHandedConstantSelf` | One-Handed Modifier | 96 |
| `EnchFortifyTwoHandedConstantSelf` | Two-Handed Modifier | 97 |
| `EnchFortifyArcheryConstantSelf` | Marksman Modifier | 98 |
| `EnchFortifyBlockConstantSelf` | Block Modifier | 99 |
| `AlchFortifyOneHanded` | One-Handed Power Modifier | 135 |
| `AlchFortifyTwoHanded` | Two-Handed Power Modifier | 136 |
| `AlchFortifyMarksman` | Marksman Power Modifier | 137 |
| `AlchFortifyBlock` | Block Power Modifier | 138 |

So each combat surface reads *two* values — the enchantment family and the potion family —
and `CombatFortifyBonus` sums them. They are not aliases: a worn item moves the first and a
drunk potion the second, so reading only one would drop half the sources. The indices are
looked up by vanilla name through `ActorValueIdentity` rather than written as numbers.

The magnitudes are percentage points, which the records' own description strings say:
"One-handed attacks do &lt;mag&gt;% more damage"
(<https://en.uesp.net/wiki/Skyrim:Fortify_One-handed>), "Bows do &lt;mag&gt;% more damage"
(<https://en.uesp.net/wiki/Skyrim:Fortify_Marksman>), "Block &lt;mag&gt;% more damage with
your shield" (<https://en.uesp.net/wiki/Skyrim:Fortify_Block>). The multiplier is therefore
`1 + points / 100`, summed before the division because the actor value is a single
accumulator and UESP's own worked example (four 40% items giving +160%) is additive.

Where each lands is in [melee combat](/engine/melee-combat.md) and
[archery](/engine/archery.md): `MeleeDamage` gained an `attackMultiplier` beside the
`bonusMultiplier` it already had for the block, and `ArcheryDamage`'s existing
`bonusMultiplier` is now fed rather than defaulted.

### The ECHG save chunk

Additive and split out of `RDLT` for the same reason `AEFF` and `SPLB` are. One entry per
owner whose enchanted weapons have spent charge or whose worn items established constant
effects; a session in which nothing enchanted fired and nothing enchanted was worn writes no
chunk at all.

Per owner, in order: the key, the cell, the charge list as `(item FormID, remaining charge)`
pairs, then the worn-item list as `(item FormID, sequence count, sequences)` groups. Both
lists are in ascending FormID order and the sequences inside a group ascend, so re-encoding
an unchanged owner produces identical bytes.

Charge travels here rather than inside `INVN` because a stack is not where charge belongs:
`INVN` entries are counts, and a charge is a per-item float that changes on a hit rather than
on a transfer. The worn-effect sequences beside it are the other half of the same fact —
which of the `AEFF` effects each worn item is responsible for — and splitting the two would
let a reload restore effects nothing could take back off.

Tolerance follows the container's rules, and this chunk has no hard stop: it carries no
closed enumeration, so a non-finite charge normalizes to zero and a sequence naming an effect
`AEFF` no longer carries simply dispels nothing when the item comes off.

## The script-facing surface

Item 19.11 (issue #474) puts the two script-facing surfaces on top of everything
above: the CTDA condition functions and the Papyrus natives. Neither adds a new
capability — both are registration over the runtimes this page already
describes — and both were chosen by measuring the vanilla data rather than by
taste.

**Conditions.** Eight functions read a `MagicConditionResolution`: one
`MagicConditionState` per actor carrying known spells, the MGEF behind every
active effect, the record each of those effects came from, the spell readied in
each hand and which hands have a cast running, beside the `SpellStore` and
`MagicEffectStore` a FormID parameter resolves against. The snapshot is built on
the main actor by `GameViewController.magicConditionResolution()` and read from a
nonisolated evaluator, exactly as the actor and detection seams are. Indices,
citations, per-function demand and the tail this milestone leaves tallied are on
[conditions](/formats/conditions.md).

The eight are readable from the app without a CLI command: the
`World > Combat & Physics > Spellcasting` section's `CombatSpellcastingStatsLabel`
carries a `Conditions (player)` block with one line per function, each run
through `ConditionProbe` against the live seam. Ready a spell and the delivery
and casting-type lines change with it; unwire the seam and each line names its
reason instead of printing a zero.

**Natives.** Eleven natives — the `Actor` spell family and `Spell.Cast` — run
through `PapyrusWorldMagicBridge` into `SpellbookRuntime`, `ActiveEffectRuntime`
and `CasterRuntime`, so a script's `AddSpell` and the Magic panel's Learn button
write the same component. None is latent. Signatures, call-site counts and the
stated gaps are on [the Papyrus VM](/engine/papyrus-vm.md).

One deviation is worth repeating here because it is about this subsystem's model
rather than about either surface. `HasMagicEffect` and its keyword variants are
documented as testing whether an actor *carries* an effect a spell could apply,
whether or not it is active; OpenSky's active-effect component holds only what
was actually applied, so all four spellings answer whether the effect is
*acting*. Every running effect answers identically.

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

Item enchantments have no destination of their own: a charge is a fact about an
equipped item, so it prints wherever equipped-item detail already prints.
`EquippedItemReadout` gained a preformatted `enchantment` line — the enchantment's
name, whether it is worn, on-hit or a staff, and `remaining/capacity charge, N
use(s) left` — which surfaces in **World > HUD & Interaction > Items**
(`ItemsStatsLabel`), in **World > Inventory & Equipment > Equipment inspection**
(`EquipmentInspectionStatsLabel`), and as the "Enchanted equipment" block of
**World > Inventory Menu > Menu** (`InventoryMenuStatsLabel`). One formatter
produces all three, so they cannot disagree about how much a weapon has left.

Covering tests for item 19.9:

- `EnchantmentChargeTests` — `floor(charge / cost)` against UESP's first published
  row, the five uses a 90/18 weapon has, the stranded partial use, the unmetered
  case, normalization of mod-authored nonsense, and the readout line.
- `EnchantmentRuntimeTests` — the profile each record shape resolves to, a landed
  hit applying its effects and draining one use, the empty weapon that applies
  nothing, resistances on a contact effect, a hit on an absent target still paying,
  recharging, a worn item granting and losing its constant effect, a constant effect
  surviving an hour of ticking, the reconcile being idempotent and difference-only,
  a contact enchantment not being worn, and the worn restriction answering both ways
  while gating nothing.
- `EnchantedItemSaveTests` — the `ECHG` round trip, an owner with no other delta,
  no chunk for a session that spent nothing, order-independent bytes, and
  normalization on the way in.
- `CombatFortifyBonusTests` — both actor-value families being read, the hand type
  selecting the pair, a bow reading the archery pair from either entry point,
  unreadable and absurd values degrading safely, and the scope point end to end: a
  Fortify One-Handed effect changing what `MeleeDamage.resolve` returns, the attack
  term not growing the block, and a Fortify Archery effect changing an arrow's
  damage.
- `MeleeCombatRuntimeTests` and `ProjectileRuntimeTests` — unchanged in behaviour
  with the new seam recorded rather than applied, which is what keeps "one
  implementation for a swing and an arrow" honest.
- `EnchantmentRuntimeRealDataTests` (env-gated) — the five UESP charge rows against
  the records, every enchanted item in the load order classifying as worn, contact
  or staff, and the vanilla armour that fails its own worn restriction.
- `EnchantmentAcceptanceRealDataTests` (env-gated) — the whole chain against the
  user's install, headless: search the load order for a metered contact enchantment
  whose effect this engine can carry out, land two hits with it, then wear a real
  Fortify One-Handed armour enchantment and read the damage number back. It leaves a
  summary in gitignored `logs/enchantment-acceptance/`. On the local install that run
  reads: `EnchWeaponFireDamage06`, 3000/3000 charge (81 uses) -> 2926/3000 (79 uses),
  target health 500 -> 440, `EnchArmorFortifyOneHanded02` worn for 20 points, melee
  damage 10.0 -> 12.0 (x1.2).

The 19.9 acceptance record, in the format
[the convention](/tools/sidebar-acceptance.md) defines:

```text
Milestone: M19.9
Sidebar path: World > Inventory & Equipment > Equipment inspection
Destination id: Destination-inventoryEquipment
Controls exercised: EquipmentInspectionTargetControl, ItemsEquipControl,
  ItemsUnequipControl
Readout: EquipmentInspectionStatsLabel (also ItemsStatsLabel,
  InventoryMenuStatsLabel)
Deterministic tests: EnchantmentChargeTests, EnchantmentRuntimeTests,
  EnchantedItemSaveTests, CombatFortifyBonusTests, InventoryEquipmentPanelTests,
  ItemsSectionTests, InventoryMenuPanelTests, EnchantmentRuntimeRealDataTests,
  EnchantmentAcceptanceRealDataTests
Local A/B (optional, never committed): logs/enchantment-acceptance/acceptance.txt
```

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

- **An NPC's spell choice ignores CSTY.** See
  [AI spell use](#ai-spell-use); decoding the combat style is a follow-up if
  runtime evidence shows the simple rule reads wrong.
- **Touch and target-location delivery do not cast.** Both are the documented
  `deliveryUnsupported` refusal and a tally entry; see
  [Delivery](#delivery-casting-at-something-else) for why each is counted rather
  than approximated. Target-actor concentration is refused for the same reason:
  holding a beam on a named actor needs targeting this build does not do.
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
- **Staff enchantments are classified and counted, not cast.** 86 of this load order's
  enchanted `WEAP` records carry a staff enchantment, whose delivery is aimed,
  target-actor or target-location rather than contact.
  `ItemEnchantmentProfile.isStaff` names them so neither the swing path nor the arrow
  path can mistake one for a contact enchantment, and
  `EnchantmentRuntimeRealDataTests` counts them; a staff *cast* is deliberately not
  wired, because the trigger is a staff attack rather than a landed hit and that
  animation seam belongs to the graph work, not to item 19.9. Half-wiring it would
  mean firing a staff's spell on contact, which is not what a staff does.
- **Recharging with soul gems is out of scope**, as item 19.9 states: an empty weapon
  stays empty. `EnchantmentLedger.recharge(_:on:)` exists for the load path and a dev
  control, not for a soul gem, and the soul-gem economy is a later milestone's.
- **The charge cost is not scaled by the wielder's skill.** UESP states that the uses go
  up with "a relevant magic skill" and that skill 100 gives "about 1.7 times the uses
  documented here", and its charge-per-use formula for a *player-created* enchantment
  carries an Enchanting-skill term instead. The two disagree about which skill is read and
  1.7 is quoted as an approximation with no formula beside it, so this engine charges the
  base cost — the number the published tables print — rather than inventing a multiplier.
- **One charge is shared between two copies of the same enchanted weapon.** Charge is keyed
  by base FormID because that is what an inventory stack is keyed by; per-instance item
  identity is the milestone that also brings tempering and item health.
- **Enchanting an item is milestone M22** and enchantment visuals on a weapon are M26. This
  item reads what the records author and applies it; nothing here creates an enchantment.
- **An NPC's timed effects do not re-establish their modifier slots on load.** The player's
  do; see [The AEFF save chunk](#the-aeff-save-chunk) for why no other actor has a
  resolvable holder at that moment.
- **An NPC wearing enchanted armour from its plugin outfit grants nothing until something
  equips.** The worn reconcile runs on an equip, an unequip and a load, not on a cell build:
  walking every resident actor's equipped set as it streams in is per-actor work this item
  did not measure, and applying constant effects to an actor nobody is fighting buys nothing
  visible. The player, who starts with nothing worn, is unaffected.

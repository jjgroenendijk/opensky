---
type: Subsystem
title: Spellcasting
description: The spellbook, where spells come from, reading a tome, readying a spell to a hand,
  the fire-and-forget and concentration casts, what refuses a cast, abilities and powers, cast
  input, saving, and the script surface.
tags: [engine, magic, casting, spells, papyrus, conditions]
---

# Spellcasting

The caster knows spells, readies one to a hand, and casts it. A cast hands its effects to the
[active effect runtime](/engine/magic.md). Spells aimed at something else are on the
[spell delivery](/engine/spell-delivery.md) page.

The rules come from reading the install and from UESP: Magic Overview
(<https://en.uesp.net/wiki/Skyrim:Magic_Overview>), Magicka
(<https://en.uesp.net/wiki/Skyrim:Magicka>), Powers (<https://en.uesp.net/wiki/Skyrim:Powers>),
Books (<https://en.uesp.net/wiki/Skyrim:Books>), and Mod File Format/BOOK
(<https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/BOOK>).

## The spellbook

The spellbook is a world state component ([runtime state](/engine/runtime-state.md)). It holds one
actor's known spells, the books it has read, the spell in each hand, and the game day each greater
power was last used.

These four live in one component because of one rule: a readied hand must name a known spell.
Forgetting a spell that is in a hand clears the hand in the same write. A save whose load order no
longer has a readied spell drops the hand instead of restoring it pointing at nothing. The
component's initializer enforces both.

A known spell this load order cannot resolve stays known, so removing a plugin destroys no progress.

## Where spells come from

1. The two start spells. UESP: "You will always know the spells Flames and Healing by the time you
   start Unbound, regardless of your race." The `SPIT` "PC Start Spell" flag is not how this works:
   in the whole vanilla load order it is set on exactly one record, `PCHealRateCombat`. Vanilla
   grants Flames and Healing from the intro quest's script, which OpenSky does not run. So the two
   are named by editor ID and resolved through the load order. A load order with neither grants
   nothing.
2. An actor's own `SPLO` list, on its `NPC_` and its `RACE`. The `SPCT` count before the list is not
   read: counting the entries gives the same answer and cannot disagree with the file. A vanilla
   race's list is its racial ability and its greater power. `NordRace` has `RaceNord` and
   `PowerNordBattleCry`.
3. Reading a spell tome.

## Reading a tome

UESP's Books page states the teaching rule: "Spell Tomes: opening the book for the first time
teaches you a spell". The BOOK format page records a mark on the `DATA` flag byte: "0x08 - Read
([verification needed] not used in static game data, flag in save game data for already read
books?)". The question mark is the wiki's own.

So reading adds the taught spell and records the book as read, and the mark stops a second reading
from teaching again. The tome stays in the inventory: neither source says it leaves. The mark is per
reader, because that is the only reading that works when an NPC picks up the book. The spell comes
from `BOOK` `DATA`'s "teaches" field, read when flag `0x04` is set.

## Readying a spell to a hand

Spells have their own equip path. The item path refuses anything the owner does not hold, because
equipping an item from nowhere is how a duplication bug hides. A spell is never held: it has no
stack, and it cannot be dropped, sold, or given. Widening the item path would remove that guard.

So the two share only what they collide over: hands. The spellbook runtime handles both directions.
Readying a spell unequips the weapon or shield in that hand, and equipping a weapon unequips the
spell in its hand.

The hands a spell takes come from its `ETYP`, walked through the [EQUP graph](/formats/shouts-equip-slots.md)
like a weapon's. One distinction matters here: `BothHands` and `EitherHand` name the same two parents
and differ only in the `DATA` "use all parents" byte.

| Reading | Meaning | What readying does |
| --- | --- | --- |
| Fixed hands | Every hand it names, at once | Fills all of them |
| Choice of hands | One of them, the equipper picks | Fills the asked hand, or refuses if the slot does not offer it |
| No hand | A slot that takes no hand, such as Voice or Potion | Refused as not hand-equippable |

In the install, over 300 spells resolve to a hand. A few do not: `WerewolfChangeFX`,
`DLC1VampireChangeFX`, and the `DLC2VoiceElementalFury` set are typed as spells but use Voice or
nothing, because a script or a shout applies them. Most powers resolve to no hand. A power belongs on
the shout button, and the voice slot is not modeled yet, so a greater power cannot be readied
anywhere yet.

## The cast

Melee and archery read their timing from the behavior graph. No casting graph runs yet, so the charge
is timed against the `SPIT` charge time. When a graph arrives it replaces this clock, and the phases
stay. UESP states both shapes:

> Some spells will trigger immediately upon being cast and can be maintained as long as held.
> Others require holding to charge the spell and releasing to cast it. Casting a spell of either
> form depletes the caster's magicka based on the cost of the spell and will continue to do so if
> the spell is maintained. Attempting to cast a spell with a cost higher than your available magicka
> will result in the failure of the attempted casting.

Fire and forget:

1. Begin resolves the readied spell, checks every refusal, and starts charging. A spell with no
   charge time is ready at once.
2. The charge builds up to the `SPIT` charge time.
3. Release checks the cost against magicka, takes it, and applies the effects.

Releasing before the charge is full casts nothing and costs nothing. Magicka is checked at begin and
again at release, because it can fall in between: something can hit the caster during a half-second
charge. The cost is the one the [spell records](/formats/magic-records.md) already computed, so a
manual cost is respected.

Concentration: begin starts the held cast. The cost is taken continuously (`cost x delta`), so the
bar moves smoothly. The effects apply once at the start and once per whole second after that, so a
held heal starts healing when it starts costing. UESP: "Concentration spells do not have a set
duration. Rather, the duration is determined by how long you hold the casting trigger." The `SPIT`
cast duration is a minimum: a release inside it keeps the cast going until it ends. When magicka runs
out, the cast ends with the insufficient magicka refusal and takes what was left. The same
one-millisecond slack as for effects keeps a held spell from skipping an application each second.

Dual casting is not implemented. UESP documents 2.2 times the effect for 2.8 times the cost, but it
is a perk, so two hands casting the same spell are two casts.

## What refuses a cast

Every refusal has a sentence, is counted, and is shown on the panel. Nothing fails silently.

| Refusal | Why |
| --- | --- |
| `noSpellReadied` | That hand holds no spell |
| `unknownSpell` | A readied spell this load order no longer has |
| `notCharged` | Released before the charge time |
| `insufficientMagicka` | At begin, at release, and during a held cast |
| `deliveryUnsupported` | A delivery OpenSky does not carry out ([spell delivery](/engine/spell-delivery.md)) |
| `abilityNotCastable` | An ability is carried, not cast |
| `powerAlreadyUsedToday` | The once-per-day rule |

UESP: "Magicka will not regenerate while you are casting a spell." The player leaves the whole
regeneration set while either hand is casting. That is wider than the source, which names only
magicka. No source says health and stamina keep going.

## Abilities and powers

An ability (`SPIT` type ability) is not cast. The actor has it. All abilities the actor knows are
applied through the effect runtime. Vanilla gives most ability entries zero duration, meaning "as
long as the actor has it". The effect runtime has no permanent mode for spells, and a zero-duration
entry there applies once. For a resistance that would be a one-off nudge wearing the name of a
permanent bonus. So those entries are counted and not applied. Timed entries apply normally.

A greater power works once per game day. The spellbook records the whole day number each power was
last used, and a second cast that day is refused. Lesser powers have no limit: "Unlike Greater
Powers, each Lesser Power can be used an unlimited number of times per day."

## Input

There is no new key. Casting uses the same two buttons as melee and archery, chosen by what the hand
holds, as a drawn bow takes the attack button from the swing:

- A spell in the right hand takes the attack button.
- A spell in the left hand takes the block button.
- A hand with no spell leaves its button to melee.

A held button becomes a begin edge and a release edge, so it does not restart the charge every frame.
Unequipping during a cast cancels the charge.

The graph is told a spell is out through hand type 9 (`spell`), the value `magicbehavior.hkx` reads
([combat graph names](/engine/combat-graph-names.md)), even though no casting clip plays yet.

## Saving

The spellbook goes in the `SPLB` chunk ([save chunks](/formats/opensky-save.md#chunks)). Readied
hands are saved, and casts are not. A readied spell is a choice the player made. A charge in
progress is frame state, and restoring it would put the player back mid-cast with magicka already
spent. Nothing rejects a spellbook on content. Duplicates, a hand naming an unknown spell, and a
used-power entry for a forgotten spell are all cleaned up by the component's initializer.

## Script surface

Eight condition functions read a magic snapshot per actor ([conditions](/formats/conditions.md)).

Eleven Papyrus natives, the `Actor` spell family and `Spell.Cast`, go through the spellbook, effect,
and caster runtimes, so a script's `AddSpell` and the panel's Learn button write the same component
([Papyrus spell natives](/engine/papyrus-spell-natives.md)).

`HasMagicEffect` and its keyword forms are documented as testing whether an actor carries an effect
a spell could apply, active or not. The OpenSky component holds only what was applied, so all four
answer whether the effect is acting.

## Controls

World > Combat & Physics > Spellcasting, below Magic Effects, because that is where a cast lands.

- Learn, Read tome, and a spell selector.
- Ready right and Ready left.
- Cast right and Cast left: each runs a whole cast without holding a button. The charge is skipped
  ahead, then the cast is released. Holding the button in walk mode reaches the same states over real
  frames.
- Readout: the spellbook, both hands, the last cast and refusal, projectiles fired, the delivery
  counts, one line per hostile entry of the last landed spell (`effect on target: base x multiplier
  = adjusted`), and a Conditions (player) block with one line per magic condition function.

Casting animations, hand effects, and sounds are not done yet.

---
type: Subsystem
title: Leveled lists
description: How a leveled list rolls against the player level, the encounter zone, a placed
  actor's difficulty, and the special loot formula.
tags: [engine, actors, inventory, leveling]
---

# Leveled lists

A leveled list (`LVLN` actors, `LVLI` items, `LVSP` spells) picks entries by level. The record
layout is on [actor records](/formats/actors.md). This page gives the rules of one roll and
how the engine feeds it.

Sources: UESP "Skyrim:Leveled Lists" (<https://en.uesp.net/wiki/Skyrim:Leveled_Lists>), the
Creation Kit pages "LeveledItem" (<https://ck.uesp.net/wiki/LeveledItem>), "LeveledCharacter"
(<https://ck.uesp.net/wiki/LeveledCharacter>), and "Encounter Zone"
(<https://ck.uesp.net/wiki/Encounter_Zone>).

## One roll

A request gives a level and a count.

- Chance none: the list gives nothing with this chance in percent. `LVLG` names a global that
  replaces `LVLD`.
- The level filter: only entries at or below the level are candidates.
- Without "all levels" (`LVLF` `0x01`), only the candidates with the highest entry level stay.
  Example: entries at levels 1, 2, 2, and 4, asked at level 3, choose between the two level 2
  entries.
- One candidate is chosen with equal chance. A list that names one item twice doubles its
  chance.
- The count: the chosen entry's count times the asked count.
- "Each" (`0x02`): the asked count is the number of separate rolls, each with count 1.
- "Use all" (`0x04`): every entry, whatever its level, each times the asked count.
- "Special loot" (`0x08`): the roll uses the special loot level below instead of the asked
  level.

A nested list rolls the same way, asked with the count of the entry that named it.

### Special loot

From the Creation Kit page "LeveledItem", with the input level as the asked level:

```text
low   = player × fSpecialLootMinPCLevelMult + fSpecialLootMinPCLevelBase
        + fSpecialLootMinZoneLevelBase + input × fSpecialLootMinZoneLevelMult
high  = player × fSpecialLootMaxPCLevelMult + fSpecialLootMaxPCLevelBase
        + fSpecialLootMaxZoneLevelBase + input × fSpecialLootMaxZoneLevelMult
level = low + (high − low) × |draw| ^ fSpecialLootWeighting,  draw in −0.5 ..< 0.5
```

`Skyrim.esm` sets four of these: `MinPCLevelMult` 0.6, `MinZoneLevelMult` 0.4,
`MaxZoneLevelMult` 1, and `Weighting` 4. The others read 0. The page raises the draw itself,
not its size. For the even vanilla weighting both give the same result; the size keeps a
fractional weighting defined.

## The level a roll asks at

- An item list in a container, an outfit, an actor's carried items, or an actor's spell list
  asks at the encounter level of where its owner stands.
- A harvested plant asks at the player's own level.
- The death item (`NPC_ INAM`, a Traits-tab field) asks at the actor's own level. It goes into
  the actor's inventory when it dies.
- The encounter level: the player level, raised to the zone's minimum when the player is
  below it, unless the zone has "match PC below minimum level", and capped at the zone's
  maximum when that is above 0. A place with no zone uses the player level. The zone is the
  reference's own `XEZN`, else the cell's, else the worldspace's.
- `iCalcLevelAdjustUp` is added and `iCalcLevelAdjustDown` subtracted. The Creation Kit page
  says only that they modify the encounter level; both are 0 in `Skyrim.esm`.

### Leveled actors

A placed actor's `XLCM` sets its difficulty. The `LVLN` hop in its template chain rolls at the
encounter level times the difficulty's `fLeveledActorMult` and `fLevelScalingMult`:

| Difficulty | `XLCM` | Multiplier (`Skyrim.esm`) | Rule |
| --- | --- | --- | --- |
| Easy | 0 | 0.33 | any entry at or below the level, as if "all levels" were set |
| Medium | 1 | 0.67 | the normal roll |
| Hard | 2 | 1 | the normal roll |
| Very hard | 3 | 1.25 | the normal roll; if it reaches the same entry level as hard, the next entry level up |
| None | absent | 1 | the normal roll |

An `LVLN` with no entry low enough gives its lowest entries. No source says what the game
does then; dropping the actor would leave the reference empty.

## One roll per placed reference

The game makes a new base record for each placed leveled actor, and keeps what it rolled
until the cell resets. OpenSky gives each placed actor and container its own
`LeveledRoll` instead: a seed from its reference key, the player level, the encounter level,
and the difficulty.

- `ActorTemplateResolver`, `ActorVisualResolver`, `InventoryBaselineResolver`, the spell,
  perk, faction, and package baselines, and the identity records all read an actor by its
  base. A caller that holds a placed reference passes its roll (`rolling(_:)`), so the
  template walk, the drawn outfit, the inventory, the spells, the name, and the voice agree.
  A call with no reference rolls for the base, seeded by the base.
- A cell build records each actor's zone and difficulty by its reference key, and each
  cell's zone for its containers, before anything rolls.
- When a cell first joins the live world, each actor and container whose records name a
  leveled list freezes the player level of that moment (`LeveledRollState`). Its rolls use
  that level until a cell reset clears it; the next attach then freezes the new level and
  rebuilds the cell. A No Respawn reference never resets, so it keeps its roll.
- A save keeps the frozen levels in the `LVRL` chunk
  ([OpenSky save](/formats/opensky-save.md)).
- Memos of derived baselines key on the base and the roll, so a new level or placement
  derives again.

`openskycli game state player` gives `level`. `state actors` gives each actor's `leveled`
hops: the list, the chosen entry, the player level it rolls at, whether that level is frozen,
the encounter level, and the difficulty.

## Where OpenSky differs

- A frozen roll keeps the player level, not the picked entries. A record change between two
  sessions, such as a new plugin, changes what the same level picks.
- Papyrus `GetLeveledActorBase` returns the placed base, not a rolled base, because OpenSky
  makes no new base records.
- `LVLG` reads the global's plugin value, not a value a script set.

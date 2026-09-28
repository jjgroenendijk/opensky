---
type: Subsystem
title: Bounty ledger and stolen goods
description: How bounties and crime counts are kept per crime faction, the violent and
  non-violent halves, how the stolen mark follows goods, and how all of it is saved.
tags: [engine, crime, factions, inventory, runtime-state, save]
---

# Bounty ledger and stolen goods

This page covers what a [crime](/engine/crime.md) leaves behind: gold owed, a count, and stolen
goods.

## The bounty ledger

The crime ledger is a world state component per criminal, with one row per crime faction: the
gold owed and the four crime counts. It has its own slot, because a bounty changes rarely, while
actor values change sixty times a second.

It is kept per crime faction, not per hold, because this engine has crime factions and not holds.
The twelve separate bounties UESP names (nine holds, the Companions, the Orc strongholds, and
Raven Rock) are twelve crime factions. `Faction.GetCrimeGold` also asks per faction.

Counts are kept beside gold because they cannot be derived from it: an unseen crime moves one and
not the other.

Rows are sorted by faction, empty rows are dropped, and a repeated faction keeps its last row. So
the same state always saves to the same bytes. A faction the load order no longer has is kept, like
a stored membership or an owned perk. Losing a bounty because a plugin came and went is the
damaging way to fail. The whole component is dropped when it is empty.

Changing or setting the gold leaves the counts alone. Paying a fine settles the debt, it does not
undo the crime. Gold never goes below zero.

### Violent and non-violent gold

Each row keeps its gold in two halves, because the Creation Kit asks for them separately: two
condition functions and two `Faction` natives each read one half, and `ModCrimeGold` has an
`abViolent` flag. The Creation Kit wiki's [Crime](https://ck.uesp.net/wiki/Crime) page lists
trespassing, pickpocketing, and theft under "Minor Crimes", and assault, murder, and escape under
"Major Crimes". The major ones are the violent half. The page was read through the Wayback
Machine ([environment](/tools/environment.md)).

The total still answers "how much is owed", because `GetCrimeGold` and a guard's fine both mean
the total. `SetCrimeGold` is documented as setting "the amount of non-violent crime gold", so
changes default to the non-violent half. Paying or serving time clears both halves.

## Stolen goods

UESP: "Stolen items in your inventory will be marked with the word 'Stolen', even if you were
able to steal the item without being detected. As long as this tag is present, the item is
considered stolen."

So the mark follows the goods, not the bounty. It is part of the stack key, not a property of the
item: "Should you steal multiple items of the same type, each item considered stolen is tracked
separately when dropped." Ten honest arrows and one stolen arrow are two stacks of one base, honest
first.

- The plain count still gives the total of both, because that is what every older question means.
- Removing items uses honest copies first. So a player with both gives up the ones with no
  consequence.
- A transfer carries the split to the other side.
- Taking from an owned container marks the goods already moved as stolen.

The item lists show one row per item, not per stack, with the stolen count beside it. Two rows
with one name and one FormID would be two identical controls acting on the same items. The
inventory row reads `[stolen]` when the whole row is stolen, and `[n stolen]` when part of it is.

A trade carries each side's split. Selling stolen goods gives the merchant stolen goods, and the
gold that comes back is honest ([vendor factions](/engine/vendor-factions.md)).

## Saving

Three chunks in the [OpenSky save](/formats/opensky-save-actor-chunks.md):

- `CRIM`: one entry per actor with a ledger, one row per faction, with the gold and the four
  counts.
- `CRVG`: the violent part of each `CRIM` row's gold. `CRIM` still writes the total, so an older
  build loads the right bounty and treats it all as non-violent.
- `STOL`: for each owner with stolen goods, one row per item with its stolen count.

`STOL` sits beside `INVN` instead of extending it. `INVN` entries have no length field, so adding
a flag to each stack would make every older build misread the whole chunk. `INVN` still writes
one row per item with honest and stolen summed. An older build loads a complete inventory that
has only forgotten which copies were stolen. `STOL` is applied after `INVN`, because the split
needs the totals in place first.

A session with no crimes writes none of these chunks.

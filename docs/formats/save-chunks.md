---
type: File Format
title: Save chunks
description: The chunks of an OpenSky save - the shared key, cell, and component encodings, what
  each chunk holds, and which state is saved and which is derived again on load.
tags: [format, save, world-state]
---

# Save chunks

This page lists the chunks inside an [OpenSky save](/formats/opensky-save.md). The exact byte
layout of each chunk is in the encoder and decoder under `opensky/Engine/Formats/Save/`, one file
pair per chunk. This page explains the shared building blocks, and the choices the code alone
does not explain.

## Shared encodings

Reference key. Names a world object in a way that survives a new load order.

| Tag | Kind | Payload |
| --- | --- | --- |
| 0 | Plugin | Plugin name string, then uint32 object ID |
| 1 | Generated | uint64 sequence from the generated-reference allocator |

A key is used instead of a FormID, because a FormID depends on the load order and would name a
different object after the plugin list changes.

Cell location. Where a reference was when it changed.

| Tag | Kind | Payload |
| --- | --- | --- |
| 0 | None | Nothing |
| 1 | Exterior | Two int32 grid coordinates |
| 2 | Interior | uint32 FormID of the cell |

Base records, such as a quest, an `INFO`, or a global, belong to no cell. Their chunks have no
cell field, because it could only ever be "none".

## RDLT components

`RDLT` holds one entry per changed reference: a key, a cell, a uint8 component count, then the
components in strictly rising tag order. Rising order makes "one value per slot" easy to check,
and gives each state one byte form.

| Tag | Component | Payload |
| --- | --- | --- |
| 0 | Enable state | One byte, 0 or 1 |
| 1 | Transform | Position x, y, z, rotation x, y, z, scale: seven float32 |
| 2 | Activation | uint32 count, open byte, "has last activator" byte, then a key if set |
| 3 | Deletion | One byte, 0 or 1 |

The tag numbers are written out case by case in code, not taken from the order of an enum. Enum
order can change in source. These numbers cannot. Every other kind of state (inventory, spawns,
and so on) has no `RDLT` tag. It travels in its own chunk, so an older build can skip it (see
[version rules](/formats/opensky-save.md#version-rules)).

## Chunk list

| Tag | Holds |
| --- | --- |
| `GALC` | Next generated-reference number. Exactly 8 bytes |
| `RDLT` | Reference changes: enable, transform, activation, deletion |
| `GVAR` | Global values that differ from the plugins, with their declared type |
| `CLOK` | Game clock: one float64, game seconds since the calendar start |
| `PSCR` | Papyrus script instances: state, "OnInit done", and variables |
| `PTMR` | Pending Papyrus update timers |
| `INVN` | Inventories that differ from the plugins: item totals and equipped items |
| `STOL` | How many of each held item are stolen |
| `SPWN` | Objects the game placed, such as dropped items |
| `QSTS` | Quest running and completed flags, reached stages, objective flags |
| `QALS` | Filled reference aliases per quest |
| `QLOC` | Filled location aliases per quest |
| `AVAL` | Current health, magicka, and stamina |
| `AVOV` | Actor value changes: base offset, permanent, and damage modifiers |
| `DETH` | Deaths, looted flag, and the corpse's resting place |
| `CBTS` | Hostility toward the player, when set on purpose |
| `DLGS` | How often each dialogue response was said |
| `AEFF` | Active timed magic effects |
| `SPLB` | Known spells, read books, used powers, and readied hands |
| `ECHG` | Enchantment charge per item, and which effects each worn item made |
| `PRKS` | Owned perks |
| `PLVL` | Player level, experience, perk points, and picks |
| `FCTN` | Faction memberships and ranks |
| `RELS` | Relationship ranks set by scripts, both directions of each pair |
| `CRIM` | Bounty per faction and the count of each crime kind |
| `CRVG` | The violent part of each `CRIM` bounty |

A chunk with nothing to say is not written. So a session that never used a feature writes the
same bytes as a build without that feature.

## Save the change, derive the rest

A save holds only what the session did. Anything that can be computed again from the records is
computed again on load. So a save loaded under a changed load order follows the new records.

- `AVAL` holds current values, not maximums. Maximums come from the race, class, and `NPC_`
  records (see [actor values](/engine/actor-values.md)). A restored actor gets new maximums and
  keeps its current value.
- `AVOV` holds a distance from the record value, not a value. A changed race or level moves the
  base, and the session's change stays on top.
- `AVOV` leaves out the temporary modifier. An active effect makes it, and the effect is in
  `AEFF`. Saving both would double every buff on each load. Each `AEFF` effect records how much of
  the modifier it owns, so the runtime can rebuild it ([magic](/engine/magic.md)).
- `AEFF` has no instant effects. Their result is already in `AVAL` and `AVOV`. It stores elapsed
  time, not remaining time, so a reloaded effect shows the same total duration.
- `PRKS` holds owned perks only. A rank is the length of the owned perk chain, and perk abilities
  are rebuilt from the owned set.
- `PLVL` holds the picks. What a pick did (10 points) is a base change in `AVOV`.
- `SPLB` holds readied hands but not a cast in progress. Restoring a cast would put the player
  back in the middle of it, with magicka already spent.
- `CBTS` holds only a hostility set on purpose. "Player in combat" comes from which nearby actors
  are hostile and alive ([combat](/engine/combat.md)). A calmed actor is written too, or it would
  be angry again after loading.
- `FCTN` holds memberships, not hostility. Hostility comes from memberships and records, so a
  plugin that changes a faction relation changes who is angry.
- `CRIM` holds crime counts as well as gold. A crime nobody saw changes the count but not the
  bounty ([crime](/engine/crime.md)).
- `DLGS` does not hold the offered topics. They follow from the records, quest state, and said
  counts ([dialogue](/engine/dialogue.md)).
- `DETH` holds the corpse's root transform only, not each bone. A reloaded corpse lies where it
  fell, in the rest pose ([ragdoll](/engine/ragdoll.md)). A corpse still falling has no resting
  place, so it is not put back in the air.
- `PTMR` holds the time left, not a deadline. Time between save and load does not count.
- `ECHG` keys charge by base item, as `INVN` does. So two copies of one enchanted weapon share one
  charge, until items get their own identity.
- `STOL` is applied after `INVN`, because it splits totals that `INVN` sets. `CRVG` is applied to
  `CRIM` the same way. An older build reads all of a bounty as non-violent.

## Fix up or reject

A value the running game can really produce is fixed up. A shape the build cannot read is
rejected. Examples:

| Case | Result | Why |
| --- | --- | --- |
| `PSCR` float that is NaN or infinite | 0 | A mod script can divide by zero |
| `PTMR` time that is NaN, infinite, or negative | 0 | The timer registry does the same on register |
| Stack count of 0 or less | Dropped | One bad stack should not lose a save |
| `AVAL` value NaN or negative | 0 | Same |
| Duplicate or unsorted stages or aliases | Sorted and merged | The type keeps that rule |
| Unknown bit in an objective flag byte | Ignored | A newer build may add a flag |
| Unknown hostility byte | Neutral | A newer build may add a state |
| Faction or perk no longer in the load order | Kept | Removing a plugin must not delete progress |
| `CLOK` NaN, infinite, or negative | Rejected | No real game can make it |
| Unknown `PSCR` value tag or `PTMR` slot | Rejected | The bytes cannot be read |
| Unknown `AEFF` source kind or mode | Rejected | The build wrote these closed lists itself |
| `SPWN` object with no cell | Rejected | Inventing a cell would drop an item in a random place |
| `AVOV` entry with no `AVAL` entry | Dropped | It would invent a health the save never had |

`PSCR` object handles and arrays are written as "none". Their identity belongs to one running VM
and means nothing after a load. The [Papyrus world runtime](/engine/papyrus-world.md) snapshots them
the same way, so a restored script sees its compiled default.

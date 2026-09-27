---
type: File Format
title: OpenSky save chunks — actors
description: Payload layouts of the AVAL, AVOV, DETH, CBTS, DLGS, AEFF, ECHG, FCTN, RELS,
  CRIM, STOL, and CRVG chunks in an .osav save.
tags: [format, save, world-state, actors, magic, crime]
---

# OpenSky save chunks: actors

These chunks hold actor state in an `.osav` file. The container, the key and cell encodings,
and the error rules are on [OpenSky save](/formats/opensky-save.md). The rules listed on
[save chunks: world and scripts](/formats/opensky-save-world-chunks.md) apply here too: a
uint32 entry count first, no chunk when empty, sorted entries, and checked counts.

A common rule: the save stores what the session did, not what the records say. Anything the
records can give again (maximum values, hostility, offered topics) is worked out again on
load. So a save made with a different load order follows the new records.

## AVAL: actor values

One entry per actor whose health, magicka, or stamina is not full: key, cell, then float32
health, magicka, and stamina (current values). Maximums are not stored; they come from the
RACE, CLAS, and NPC_ records ([actor values](/engine/actor-values.md)). A value that is
negative or not finite becomes 0. Minimum entry size: 20 bytes.

## AVOV: actor-value overrides

One entry per actor with any of the 164 actor values changed: key, cell, uint32 value count,
then value records in ascending index order:

| type | field | notes |
| --- | --- | --- |
| int32 | index | vanilla actor-value table index |
| float32 | baseOffset | distance from the base the records give |
| float32 | permanent | permanent modifier |
| float32 | damage | damage modifier, never positive |

`baseOffset` is a distance, not a value, so a changed race or level moves the base and the
session's change stays on top. The temporary modifier is not stored: the magic effect that
made it makes it again (`AEFF`), and storing both would double every buff.

`AVOV` replaced an older tag, `AVGN`, which stored absolute values. The shapes are the same
and the meanings differ, so a new tag was needed. An `AVOV` entry needs an `AVAL` entry for the
same actor; without one it is dropped. An index outside the table is dropped. Sizes: 12
bytes minimum per entry, 16 per record.

## DETH: deaths

| type | field | notes |
| --- | --- | --- |
| key, cell | | the actor |
| uint8 | isDead | non-zero when dead |
| uint8 | wasLooted | non-zero once the corpse was searched |
| uint8 | present | non-zero when a resting transform follows |
| bytes | resting | position, rotation, scale as in an `RDLT` transform |

A corpse that was still falling has no resting transform, so it does not reload in the air.
Only the root transform is stored, not the bone pose. A reloaded corpse lies in the rest pose
([ragdoll](/engine/ragdoll.md)).

## CBTS: hostility

Key, cell, and a uint8: 0 neutral, 1 hostile. An actor made neutral again is still written,
or it would reload angry. An unknown byte reads as neutral, so a newer build can add a
value. Whether the player is in combat is not stored; it follows from which actors are
hostile and alive ([combat](/engine/combat.md)). Minimum entry size: 9 bytes.

## DLGS: dialogue

One entry per `INFO` that was said: the INFO key and a uint32 said count. No cell, because an
INFO is a base record. A count of 0 is never written and is dropped on read. The offered
topics are not stored ([dialogue](/engine/dialogue.md)). Minimum entry size: 11 bytes.

## AEFF: active magic effects

Key, cell, uint32 effect count, then effects:

| type | field | notes |
| --- | --- | --- |
| uint64 | sequence | per-actor application number, ascending |
| uint32 | sourceKind | 0 potion, 1 ingredient, 2 spell, 3 enchantment |
| key | sourceRecord | the ALCH, INGR, SPEL, or ENCH |
| key | effect | the MGEF |
| optional key | caster | presence byte, then the key |
| uint32 | mode | 0 held modifier, 1 per second |
| uint8 | detrimental | 1 when the magnitude is taken off |
| float32 | duration | seconds, from `EFIT` |
| float32 | elapsed | seconds since it started |
| uint32 | paidSeconds | whole seconds a per-second effect has paid |
| optional key | stackKeyword | the no-stack keyword |
| uint32 | valueCount | records that follow |
| bytes | values | per record: int32 index, float32 magnitude, float32 applied |

`elapsed` is stored, not the time left, so a reloaded effect shows the same total duration.
`applied` is how much of the temporary modifier each effect owns, so the modifier is rebuilt
from it ([magic](/engine/magic.md)). Instant effects are not stored; their result is already
in `AVAL` and `AVOV`. An unknown `sourceKind` or `mode` is `invalidValue`. An effect with no
duration or no values is dropped. Sizes: 12 bytes minimum per entry, 49 per effect, 12 per
value.

## ECHG: enchanted items

Key, cell, then a uint32 charge count with charge records (uint32 item FormID, float32 charge
left), then a uint32 worn count with groups (uint32 item FormID, uint32 sequence count, then
uint64 `AEFF` sequence numbers). All lists ascend.

The item is its base FormID, as in `INVN`. So two copies of one enchanted weapon share one
charge ([magic](/engine/magic.md#item-enchantments)). The worn groups say which `AEFF`
effects each worn item owns, so taking it off removes them. A charge that is negative or not
finite becomes 0. A sequence that names no effect removes nothing. Sizes: 16 bytes minimum
per entry, 8 per charge, 8 minimum per worn group, 8 per sequence.

## FCTN: factions

Key, cell, uint32 membership count, then memberships: the FACT key and an int8 rank. The rank
is signed as the `NPC_` `SNAM` rank is (xEdit `itS8`), and vanilla uses negative ranks. A
repeated faction keeps its last rank. A faction that the load order no longer has is kept,
because removing a plugin must not delete progress. Hostility is not stored here
([combat](/engine/combat.md)). Sizes: 12 bytes minimum per entry, 8 per membership.

## RELS: relationships

Key, cell, uint32 override count, then overrides: the other actor's key and an int8 rank, 4
down to -4. The rank is the signed `GetRelationshipRank` number, not the `RELA` `DATA` word
([relationships](/formats/relationships.md)). A rank outside -4 to 4 is kept. Both actors of
a pair store the row. Sizes: 12 bytes minimum per entry, 8 per override.

## CRIM: crime

Key, cell, uint32 row count, then rows:

| type | field | notes |
| --- | --- | --- |
| key | faction | the crime faction |
| int32 | gold | bounty; never negative |
| uint32 x 4 | counts | theft, assault, murder, trespass |

The counts are read by position, so a build that adds a crime kind reads it as 0 from an
older file. Counts are stored beside the gold because a crime nobody saw adds a count but no
gold ([crime](/engine/crime.md)). A negative value becomes 0. A faction the load order no
longer has is kept. Sizes: 12 bytes minimum per entry, 27 minimum per row.

## STOL: stolen goods

Key (the owner), uint32 row count, then rows of uint32 item FormID and int32 stolen count.
No cell. `STOL` is applied after `INVN`, because it splits the totals `INVN` holds. A row
for an owner with no inventory is dropped, and a stolen count above the total is cut to the
total. Sizes: 11 bytes minimum per entry, 8 per row.

## CRVG: violent crime gold

Key, uint32 row count, then rows of the faction key and int32 violent gold. A bounty has a
violent part and a non-violent part. `CRIM` holds the sum; the non-violent part is the sum
minus this value. An older build skips `CRVG` and reads all gold as non-violent. Only rows
with a violent part are written. A violent part above the total is cut to the total, and a
row for a faction with no `CRIM` row is dropped. Sizes: 11 bytes minimum per entry, 11 per
row.

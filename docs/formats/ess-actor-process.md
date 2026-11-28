---
type: File Format
title: Skyrim Save Actor Process Data
description: The AI process part of an actor's change form in a Skyrim SE save - when it is
  present, its blocks, the package encoding, and which parts are not decoded.
tags: [format, save, ess]
---

# Skyrim save actor process data

An actor that has an AI process writes its process data right after the animation part of its
change form ([change forms](ess-change-forms.md#actor-data-after-the-animation-part)). The
data has no length in front. Some parts are not decoded, so a reader cannot always find its end.

Types are as in [ESS](ess.md#basic-types). A `refID` is the usual 3 bytes, and 3 zero
bytes mean none. A string is a `uint16` length and the characters, with no terminator. A
"relative time" is a `float32` game time saved as the stamp minus the current game time.

## Which blocks follow

The first `uint32` of the actor header is the process level.

| Level | Blocks |
| --- | --- |
| `0xFFFFFFFF` | None: the actor has no process |
| 3, low | Common part |
| 2, middle-low | Common part, middle-low block |
| 1, middle-high | Common part, middle-low block, middle-high block |
| 0, high | As level 1, with the high block inside the middle-high block |

Only saves older than version 0x3E leave fields out. A version 74 save writes every field below.

## Common part

1. `float32` last update hour, `float32` last update day.
2. `uint8` flag. When 1: 48 bytes; a `uint32` count of (`int32` actor value, 4 bytes, `uint8`); a
   `uint32` count of (`int32` index, 4 bytes, `uint8`).
3. The current package ([below](#package)).
4. `uint8`, then `float32` essential-down time. On load a time over `fEssentialDeathTime` (20 in
   `Skyrim.esm`) becomes 0.
5. `refID`, 4 bytes, 4 bytes, 4 bytes, `uint8`, `uint16`.
6. Relative time and 4 bytes, then `refID` of a form list.
7. `vsval` count of `refID`.
8. `uint32` count of (`refID` item, `refID` equip slot): the equipped item in each slot.
9. `refID`, `refID`, `uint8`, `refID` topic.

## Package

- `refID` package. A none ends the package here.
- Only for a package made at runtime: a `uint8` procedure type. When it is not `0xFF`, the
  [made package's data](#packages-made-at-runtime) follows.
- `uint8` running-data type. `0xFF` means none; any other value is followed by
  [its data](#running-data).
- `uint32`, `uint32`, `uint32` package flags, `uint16` interrupt flags, `uint8` status bits,
  `uint8` preferred speed, `refID` target.

### Running data

| Type | Procedure | Data |
| --- | --- | --- |
| 12 | Sandbox | 28 bytes, 4 `uint8`, 4 bytes, `uint8`, `int32` time from now, 16 bytes, 7 bytes, 3 `refID`, then a `vsval` count of (12 bytes, `refID`) |
| 13 | Patrol | 12 bytes, 2 `uint8`, 4 bytes, then a `vsval` count of `refID` |
| 14 | Guard | 12 bytes, `refID` actor, 12 bytes, `uint8`, then a `uint8` flag. When 1, a [target](#target) |
| 18 | Template package | A `vsval` count of (`uint8` variable index, string type name, a value of that type), then a string branch type and that branch's data. Only the values that differ from the template are saved |
| 2, 16 | Escort, use weapon | Not decoded |

The typed values and the branch data of a template package are not decoded. Most vanilla packages
are template packages, so most actors near the player cannot be read past their package.

### Target

`uint8` kind, 4 bytes, then by kind: 0, 1, and 3 a `refID`; 2, 4, and 5 4 bytes.

### Packages made at runtime

The game makes alarm, flee, dialogue, spectator, and trespass packages while it runs. Each saves
12 bytes of package data, then a `uint8` mask:

- bit 1: a place. `uint8` kind, `uint32` radius, then by kind: 0 to 4 a `refID`; 5, 8, 9, and 10
  4 bytes; 11 1 byte;
- bit 2: a [target](#target);
- bit 4: data of the package type, not decoded.

Then a `uint32`, and by package:

| Package | Data |
| --- | --- |
| Alarm | `vsval` count of (`uint8`, `uint16`), then `uint8` |
| Dialogue | 3 `refID`, 2 `uint8` |
| Flee | 2 `uint8`, 12 bytes, 4 bytes, 3 `uint8`, 2 `refID`, then a `vsval` count of `refID` |
| Spectator | `int32` relative time, 12 bytes, `uint8`, 12 bytes, then a `vsval` count of (4 bytes, `int32` relative tick, 4 bytes, 12 bytes, 12 bytes, `uint8`, `uint8`, `refID` actor, `refID` actor) |
| Trespass | 20 bytes, then 3 bytes |

Which procedure type number marks which package is not known.

## Middle-low block

4 bytes.

## Middle-high block

1. 12 bytes, `uint8`, 12 bytes, 8 bytes, 3 `uint8`, 4 bytes, `uint8`, 8 bytes, 2 `uint8`, `uint16`.
2. `int32` furniture marker index, -1 for none; `uint8`, 4 bytes, 4 bytes; 3 `uint8`.
3. `refID` idle, `refID` idle, `refID` actor, `refID` furniture, `refID` idle.
4. 12 bytes, 4 bytes, `uint8`, 4 bytes, `uint32`.
5. `vsval` count of `refID` actor.
6. A second package, encoded as [above](#package).
7. `vsval` count of (`refID`, `uint8`, `vsval`, then a `vsval` length and that many bytes).
8. `refID` spell or other magic item.
9. `vsval` count of (`refID`, `int32`, `uint8`, `uint32`, `refID`, `refID`, 5 `uint8`).
10. 12 bytes, `refID` actor, 4 bytes, 4 bytes, `uint8`, 4 bytes, 6 `uint8`.
11. The [high block](#high-block), at level 0 only.
12. `uint8`, the last byte of the block.

## High block

The values named here are the ones the conversation and idle rules use
([random conversations](../engine/random-conversations.md#what-a-save-keeps)).

1. `uint8` busy talking.
2. 2 `uint8`, `uint16`, 4 bytes, 4 bytes.
3. `float32` greeting timer, then 12 bytes.
4. `float32` time of the last conversation step, then 4 bytes.
5. `float32` idle chatter timer.
6. 3 `uint16`, `uint8`, 12 bytes, 12 bytes, 24 bytes.
7. `uint8`, 4 bytes, `uint8`, 4 bytes, `uint8`.
8. 4 bytes, `float32` countdown.
9. `uint8`, 16 bytes, 2 `uint8`, 8 bytes, 2 `uint8`.
10. 4 bytes (taken modulo 12 on load), 4 bytes, `uint8`, 4 bytes.
11. `float32` social timer, for random conversations.
12. 8 bytes, 3 `uint8`, 4 bytes, 2 `uint8`.
13. `float32` recent-partner timer.
14. `uint8` 0, `uint8` flag.
15. 4 `refID`; the second is always none.
16. `refID` conversation partner.
17. `refID` idle being played, `refID` the idle's target. On load the idle plays again on the
    target.
18. `refID`, then 6 (`refID`, `uint8`).
19. `uint8` flag. When 1: a `vsval` count of (string, string, 4 bytes, 4 bytes, `uint8`, 3 `refID`,
    `uint8`), then `int16`, then 4 `refID`.
20. A `vsval` count that is always 0, followed by 43 bytes (36 bytes, 4 bytes, `refID`) for each
    entry the actor holds. A reader skips 43 bytes per entry it cannot count, so this list must
    be empty for the reader to stay in step.
21. `uint8` flag. When 1: 4 bytes, 12 bytes, relative time, `refID`.
22. `vsval` length and that many bytes: body movement state.
23. `uint8`, `uint8` 1.
24. `vsval` count of (4 bytes, 4 bytes, `refID` topic, `refID` topic info).
25. `vsval` count of (`refID`, `refID`, `refID`, 4 bytes, relative time, `uint8` flag; when set:
    4 bytes, 3 `uint8`, 36 bytes, 2 relative times, 4 bytes).
26. 4 bytes, `refID` shout, 24 bytes.
27. `uint8`, 4 bytes, 4 bytes, relative time, relative time, `refID` package, `refID`.
28. String.
29. `uint8` flag. When 1, an animation part: `uint8` flag, `uint8`; `uint8` flag and, when set, a
    string and a `uint32`; `uint8` flag and, when set, a string; then one entry for each animation
    slot from slot 3 up, probably two; then `uint16`, `uint16`, `uint32`, `uint8`. An entry is a
    `uint8` present flag and, when 1, a `uint8` kind. Kind 0 is a `uint8`, a `uint32` n, and n
    12-byte values. Kind 1 is not decoded.
30. 5 `uint8`, 4 bytes, 2 `uint8`.
31. `int32` waiting request, -1 for none.
32. `refID` actor, `refID` magic item, relative time, 4 bytes.
33. `uint8` set when a conversation starts, `uint8`.
34. `refID` topic info, 2 `uint8`, 4 bytes, relative time, 2 `uint8`.

## Not decoded

- Template package values and branch data, escort and use-weapon running data, and the type data
  of packages made at runtime.
- The number of animation slots in the high block, and slot kind 1.
- The meaning of most unnamed values.

No part of this page has been checked against a real `.ess` file yet.

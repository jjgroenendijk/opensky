---
type: Subsystem
title: Detection schedule
description: When the game checks one observer and target pair, who asks for the check, and
  the limits OpenSky puts on the perception pass.
tags: [engine, ai, perception, detection]
---

# Detection schedule

The [detection](detection.md) page gives the formula for one observer and one target.
This page says when that check runs.

## Who runs detection in the game

- Each actor runs its detection pass inside its own AI update. The update must not have ended
  early: the actor has 3D, its cell is attached, it is not the player, and it is not held in
  [dialogue mode](dialogue-mode.md).
- A pass runs when the real time since the actor's last pass is over its interval. The next
  interval is random between `fDetectionUpdateTimeMin` (1 second) and `fDetectionUpdateTimeMax`
  (2 seconds). In a complex scene it is between 2.5 and 5 seconds. A scene is most likely complex
  with more than `iAINumberActorsComplexScene` (20) actors in the high process level.
- `iUpdateDetectionsAllowedPerFrame` (100) limits the checks in one frame. Each observer and
  target pair counts as one. Once the limit is reached, no new pass starts, and the actor tries
  again on the next frame.
- A pass checks each actor in the high process level that has 3D, then the player.
- The observer keeps tracking a target only for a reason. There are nine: the observer is
  [hostile](hostility.md#aggression-draws-the-weapon) to it, the target is in combat, a
  teammate is involved, the observer watches for crime or trespass, the target is a corpse within
  a set range, and others. Without a reason the detection state of the pair is dropped. An old
  state expires after `fDetectionStateExpireTime`.
- An actor that runs its warn package for the aggro radius skips one of the hostility reasons.
- Combat can start on any result of 0 or more ([keeping a combat target](detection.md#keeping-a-combat-target)).
  `iAICombatMinDetection`, `fPlayerDetectActorValue`, `fSneakStealthBoyMult`, and
  `fSneakNoticeMin` are never read. The aggro radius rule is in
  [combat behaviour](aggro-radius.md).

A pair's check then repeats at an interval that depends on who asks:

| Who asks | Interval | A stored result is reused when younger than |
| --- | --- | --- |
| A combat group, for a target beyond 2,048 units | 1.5 s | 3 s |
| The actor itself, or its group for the player or a target within 2,048 units | 1 s | 2 s |
| A group member whose own combat target is another NPC | 0.5 s | 1 s |
| A group member whose own combat target is the player | 0.25 s | 1 s |

The shortest interval any asker gives wins. Checks run only while the observer and the target
are both within 8,192 units of the player.

## Limits and repeatability

Every observer against every target, with a ray per pair, grows fast with the world. Three
limits keep it bounded, and each reports what it cut:

- At most 64 pairs. The nearest pairs win, and a counter shows how many were dropped. A silent cut
  would read as "nothing else was near".
- At most 8 pairs evaluated per step, in turn, in a fixed order. A pair gets the time since
  its last evaluation. So slicing changes when a level is computed, not where it ends up.
- An observer in combat checks a target that is neither the player nor its combat target at
  0.75 times the range. OpenSky divides the distance by 0.75, which gives the same result.
- [WARNING] The game checks a pair every 0.25 to 2 seconds, by who asks. OpenSky checks a pair
  far more often, so its levels rise smoothly. The game's intervals are not built.
- At most 8 steps per frame, like combat and actor values.

The list of actors is refreshed once per frame and sorted by `ReferenceKey`. Every change is a
pure function of the elapsed time. So two runs with the same inputs give the same levels.

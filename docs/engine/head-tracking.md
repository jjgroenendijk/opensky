---
type: Subsystem
title: Head tracking
description: How an actor chooses what it looks at, and how the neck and head turn on top of the
  clip it plays.
tags: [engine, animation, actor, dialogue, scenes, app-ui]
---

# Head tracking

A loaded actor turns its neck and head toward what it looks at. The turn is drawn on top of
the clip the actor plays, so it works with any idle, walk, or combat clip. It needs each actor to
have its own skinning palette ([actor animation](/engine/actor-animation.md)).

## What an actor looks at

The first rule that applies wins:

1. A given target. The dialogue menu makes the speaker look at the player for the whole
   conversation. A scene line makes its speaker look at the action's `HTID` alias for the
   length of the line ([scene records](/formats/scenes.md)). Both count as dialogue.
2. The player, when the player is within 384 units, and for `fAIHoldDefaultHeadTrackTimer`
   seconds after the player leaves that distance.
3. Nothing: the head returns to the body's forward axis.

A dead actor does not look at anything. The 384 units are OpenSky's own number.

## How the head turns

The look is two angles measured from the body's forward axis: yaw to the side and pitch up or
down. The target is taken into the actor's own frame through the drawn transform, and the
angles are measured from an eye point 120 units up. So the turn does not depend on how each
bone's own axes point.

The limits and the speed come from the game settings. The table gives the vanilla values. The
values come from the Creation Kit wiki page "Category:Settings"
(<https://ck.uesp.net/wiki/Category:Settings>), and were read again from `Skyrim.esm` with
`openskycli gmst list`. A setting that `Skyrim.esm` does not hold keeps the wiki value.

| Rule | Setting | Vanilla |
| --- | --- | --- |
| Largest yaw | `fTrackXY` | 60 degrees |
| Pitch range | `fTrackMinZ`, `fTrackMaxZ` | -60 to 60 degrees |
| Slowest turn, at or below the smaller angle still to go | `fHeadTrackSpeedMin`, `fHeadTrackSpeedMinAngle` | 60 degrees per second, 5 degrees |
| Fastest turn, at or above the larger angle still to go | `fHeadTrackSpeedMax`, `fHeadTrackSpeedMaxAngle` | 200 degrees per second, 10 degrees |
| Dead zone | `fTrackDeadZoneXY`, `fTrackDeadZoneZ` | 8 degrees on each axis |
| Hold on the player | `fAIHoldDefaultHeadTrackTimer` | 5 seconds |
| Target further round than | none | 108 degrees: behind, so the actor looks ahead |
| Neck share of the turn | none | 40 percent; the head takes the rest |

Between the two speed angles the speed is a straight blend. A head at rest does not move while
its goal stays inside the dead zone. Once the goal leaves it, the head turns until it arrives.
A head with no target always turns back to forward.

`fTrackXY`, `fTrackMinZ`, and `fTrackMaxZ` are not in `Skyrim.esm`.

[WARNING] The wiki gives these settings no units. OpenSky reads the angles as degrees and the
speeds as degrees per second, because a 60 degree yaw matches what an actor does in the game.
The pitch range is wider than the 30 degrees OpenSky used before; it was not compared with the
game. The behind angle and the neck share are OpenSky's own.

### Glances

While an actor looks at a target, it can glance away. Each cycle lasts the reset timer. At the
start of the cycle the actor looks straight at its target. After the pick timer it glances by a
random offset on each axis, with a random sign, for a random stay time. Then it looks back. In
dialogue the `fAIHeadTrackDialogue...` settings apply, else the `fAIHeadTrack...` ones.

| Part | Idle setting | Dialogue setting | Vanilla |
| --- | --- | --- | --- |
| Offset size | `fAIHeadTrackOffsetRandomValueMin`, `...Max` | `fAIHeadTrackDialogueOffsetRandomValue` | 0 degrees |
| Pick timer | `fAIHeadTrackPickNewOffsetTimer` | `fAIHeadTrackDialoguePickNewOffsetTimer` | 2 seconds |
| Reset timer | `fAIHeadTrackResetPositionTimer` | `fAIHeadTrackDialogueResetPositionTimer` | 4 seconds |
| Stay time | `fAIHeadTrackStayInOffsetMin`, `...Max` | `fAIHeadTrackDialogueStayInOffsetMin`, `...Max` | 1 to 2 seconds |

Each actor's cycle starts at a point taken from its form ID, so a crowd does not glance
together.

[WARNING] Every offset is 0 in vanilla, so a vanilla actor never glances, and the game could
not be observed to confirm this reading. How the timers fit together, and degrees as the unit,
are OpenSky's reading of the names.

The neck bone `NPC Neck [Neck]` turns first, about its own position, with every bone under it.
Then `NPC Head [Head]` turns about its new position, with every bone under it, such as the eyes.
A skeleton without these bones, such as a horse, is left as it is.

A speaking actor's [lip track](/formats/lip.md) adds a small pitch, yaw, and roll on top of
the look, through the same two bones and shares. Roll tilts around the forward axis. The lip
track's turn has no limit and no speed: it follows the recorded curve.

The eyes move as face morphs, not as bones ([face morphs](/engine/face-morphs.md)).

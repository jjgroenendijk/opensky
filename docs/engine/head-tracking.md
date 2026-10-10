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
   length of the line ([scene records](/formats/scenes.md)).
2. The player, when the player is within 384 units.
3. Nothing: the head returns to the body's forward axis.

A dead actor does not look at anything. The 384 units are OpenSky's own number.

## How the head turns

The look is two angles measured from the body's forward axis: yaw to the side and pitch up or
down. The target is taken into the actor's own frame through the drawn transform, and the
angles are measured from an eye point 120 units up. So the turn does not depend on how each
bone's own axes point.

| Rule | Value |
| --- | --- |
| Largest yaw | 60 degrees |
| Largest pitch | 30 degrees |
| Target further round than | 108 degrees: behind, so the actor looks ahead |
| Neck share of the turn | 40 percent; the head takes the rest |
| Turn speed | 180 degrees per second |

The neck bone `NPC Neck [Neck]` turns first, about its own position, with every bone under it.
Then `NPC Head [Head]` turns about its new position, with every bone under it, such as the eyes.
A skeleton without these bones, such as a horse, is left as it is.

[WARNING] The limits, the shares, and the speed are OpenSky's own. They are not read from the
game, which drives the head through its behaviour graph.

## Controls

World > Dialogue & Voice > Face Morphs:

- Head tracking: turns head tracking on or off. Off puts every head back to forward.
- The readout shows what the selected actor looks at, and its yaw and pitch.

The launcher's Graphics page has the same switch under Characters. It is a persisted player
setting, so the choice survives a restart.

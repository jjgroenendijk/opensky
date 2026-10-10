---
type: Subsystem
title: Dialogue camera and speaker focus
description: How a conversation frames the speaker's head without changing the camera mode,
  where each framing number comes from, and how the speaker is stopped, turned, and held.
tags: [engine, dialogue, camera, npc, packages]
---

# Dialogue camera and speaker focus

While the dialogue menu is open, the view frames the speaker's head, and the speaker stops and
faces the player. Leaving gives back the player's view and the speaker's routine. Topic
selection is on the [dialogue runtime](/engine/dialogue.md) page.

## An override, not a camera mode

The camera mode is what the player chose to look through, and `G` changes it. A conversation is
something that happens to the player. So the dialogue camera writes the camera pose on top of
whatever mode is active, and remembers what was there. The mode itself never changes.

The swap is undone at the start of each input frame, before anything simulates, and applied
again at the end. That order matters. The walk controller reads the player's facing from this
same pose, and the body is placed by its yaw. A frame that simulated with the dialogue pose would
turn the player around to face themselves. Between frames the dialogue pose stands. The render
passes read it, and so does the audio listener: a conversation is heard from where it is seen.

## Where the framing comes from

Nothing in the readable install describes conversation framing. `openskycli gmst list --prefix f`
on `Skyrim.esm` has no `fDialogueCamera*`, no `fOverShoulder*`, and no camera framing setting at
all. The only nearby distances are `fAIInDialogueModeWithPlayerDistance` (500) and
`fAIInDialogueModewithPlayerTimer` (60), which decide when an actor thinks it is in a
conversation, not where a camera stands. The `fAIHeadTrackDialogue*` family is head tracking. The
rest is in the game executable, which OpenSky does not read.

So the framing comes from the same two measured things as the
[third-person camera](/engine/player-camera.md): the player capsule and the field of view. The one
taste value, how much of the frame the subject fills, is the third-person camera's, so the engine
makes that choice only once.

| Quantity | Value | Source |
| --- | --- | --- |
| Target | The speaker's `NPC Head [Head]` bone | The posed skeleton each frame. The capsule's eye height if the actor has no skeleton |
| Framed height | 96 units | The head in the middle, down to the capsule's middle, and the same distance above the head |
| Framing distance | about 126 units | `(span / 2 / fill) / tan(fov / 2)` at a 65 degree vertical field of view |
| Shoulder offset | 24 units | One capsule radius, on the same side as third person |
| Space behind the player | 24 units | The third-person minimum distance, so the lens clears the player's body |
| Field of view | 65 degrees | The shared world angle, whatever mode the conversation interrupted |

The shot: the camera stands on the player's side of the speaker, one shoulder off the line of
sight, so the view is three-quarter and not flat. It sits at the height of the player's eye, so a
taller speaker is seen from below. Its distance from the speaker is the framing distance, or the
player's own distance plus the space behind, if the player stands farther away. That keeps the
player's body in the frame in third person. In first person the body stays hidden, as in the game:
the eye is just behind the player's head, so a helmet would fill the view. Standing close gives a
tight shot. Talking from across the room puts
the camera at the player's shoulder, not floating between the two.

The camera is pulled in by the same collision sweep as the third-person camera. It never comes
closer to the target than one capsule radius, where it would be inside the speaker's head.

The target is updated every frame, not fixed at the start. The head is a bone of a running
animation, and the player can walk around the speaker during the conversation.

## Speaker focus

Starting a conversation stops the speaker, turns it to face the player, and holds its package.
Leaving gives all three back. Each change goes through the system that already owns that thing,
so nothing here can disagree with what the AI does on the next frame.

| What | How | On release |
| --- | --- | --- |
| Walking | The mover stops where it stands | Nothing. A resumed package asks for its own movement |
| Facing | A facing hold in the movement runtime | The hold ends. The actor keeps the direction it reached |
| Package | The package is suspended | The suspension lifts, and the package is selected again |

The facing hold turns the whole actor in place, at the same turn rate a walking actor uses. It
sends a "standing still" drive every frame, so the animation keeps the idle clip. It does not
count against the limit of eight movers. A turn has no path, no collision sweep, and no new
search, so the CPU budget that limit protects does not apply ([navigation](/engine/navigation.md)).
Starting a walk ends a hold, and starting a hold ends a walk, because one yaw has one owner.
During the conversation the speaker turns its head toward the player
([head tracking](/engine/head-tracking.md)).

Suspension is a latch, not a saved plan. While an actor stood in a conversation, the world moved
on. On release it needs the package its schedule names now. So the package is selected again from
scratch, as after [combat](/engine/combat.md).

## Controls

World > Dialogue & Voice > Dialogue Camera:

- Force camera: shows the framing on any actor without a conversation. A conversation needs an
  actor with something to say, within reach. The framing must be checkable on any actor in the
  cell. An open conversation wins over the force, so forcing and then talking to someone else
  cannot leave the view on the wrong actor.
- Target: which actor the forced camera frames.
- Overlay: draws a yellow cross on the pivot, a cyan line from the player's eye to it, and a
  magenta line along the camera's own axis ([navigation](/engine/navigation.md)). It is drawn
  from the last resolved pose, so it cannot disagree with the frame it is drawn over.
- Readouts: the camera pose and the speaker's state.

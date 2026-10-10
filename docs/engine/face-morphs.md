---
type: Subsystem
title: Face morph runtime
description: How named FaceGen expression weights are joined on the CPU, applied before skinning
  on the GPU, kept safe across frames, and matched in the shadow pass.
tags: [engine, facegen, morph, animation, metal, actor, app-ui]
---

# Face morph runtime

A face morph moves face vertices to make an expression, such as `Aah` for an open mouth. Each
loaded actor has its own named weights from 0 to 1. The file format is on the [TRI](/formats/tri.md)
page. How the head is found is on the [actor records](/formats/actors.md#facegen-paths)
page.

## Which meshes morph

The face model keeps a "FaceGen head" role after assembly. Only that model gets morphs, never the
body or a weapon. OpenSky joins the race's default head parts with the `NPC_` head parts, drops
duplicate FormIDs, and pairs each head part that has an expression TRI with its face shape.

Face morphs and skeletal animation are separate. Neither owns or resets the other.

## Joining targets on the CPU

When the actor is built, each target is prepared once:

1. Scale every stored position by the target's float scale.
2. Compute base normals from the triangles, weighted by area.
3. Add the target's position changes and compute its normals again.
4. Store the normal change: morphed normal minus base normal.

When a weight changes, the CPU builds one array of changes for all vertices. Each weight is
clamped to 0 to 1, and each active target adds its scaled position and normal change, in a fixed
order. A name that does not exist changes nothing and is counted.

This is done on the CPU on purpose. Weights change at human speed, a few names at a time. The GPU
then reads one ready array per frame. It never has to loop over targets per vertex.

## GPU data

Each vertex change is two `SIMD3<Float>`: position at byte 0, normal at byte 16, 32 bytes in all.
It is buffer 14, vertex attributes 8 and 9.

Morph changes are added before skinning. The TRI changes are in the face's pose before skinning.
Adding them after skinning would not turn them with the actor's pose.

The mesh in the cache stays shared and unchanged. Each actor's placement carries its own change
buffers, and a morph pipeline is chosen for it.

## Frame safety

Each morph buffer has one slot per frame in flight. Just before encoding, the renderer copies the
current changes into the active slot. This happens at most once per frame, covering both the
shadow and scene passes. So the CPU never writes into memory the GPU is still reading.

The morph buffer is part of the draw grouping key. Two actors with the same face mesh but
different expressions are never drawn as one instanced draw.

## Shadows

The shadow pass adds the same changes before skinning. So a mouth cannot move in the picture while
its shadow keeps the rest pose.

## Automatic expressions

Every loaded face blinks, and a speaker's face shows the emotion of the line it says. These
weights are a third layer, added to the manual and lip weights and clamped like them.

A dialogue response's `TRDT` emotion picks one target of the expression TRI, at the response's
emotion value out of 100. The names were read from `malehead.tri` on the install:

| Emotion | Target |
| --- | --- |
| Anger | `DialogueAnger` |
| Disgust | `DialogueDisgusted` |
| Fear | `DialogueFear` |
| Sad | `DialogueSad` |
| Happy | `DialogueHappy` |
| Surprise | `DialogueSurprise` |
| Puzzled | `DialoguePuzzled` |
| Neutral | nothing |

In the dialogue menu the emotion holds until the next response or the end of the conversation.
A scene line holds it for the line's length.

A blink closes `BlinkLeft` and `BlinkRight` together over 0.2 seconds. Each actor blinks every 3
to 6 seconds, at a gap and an offset from its FormID, so a crowd does not blink together. The
blink timing is OpenSky's own. The weights are uploaded only when they change, so a face between
blinks costs nothing.

## Controls

World > Dialogue & Voice > Face Morphs follows the current dialogue speaker, or else the actor
under the crosshair. It has a target list, a weight slider, a reset button, and a readout of
targets, active weights, file pairs, missing pairs, writes to unknown names, and the automatic
expression. Checkboxes turn blinking, dialogue expressions, and
[head tracking](/engine/head-tracking.md) on or off. A nonzero weight or a checkbox turned off
marks the panel as changed, and the panel's reset clears all weights and turns all three on.
The launcher's Graphics page has the same three switches under Characters. Both places write
one persisted player setting each, so a choice survives a restart.

## Failures

A TRI parse or pairing failure affects only that actor. The actor and its baked head still draw.
The failures are kept for the readout. Any pair that worked still morphs.

## Not done yet

- `.lip` timing, and turning dialogue time into weights.
- Race sliders and character creation morphs.
- Body morphs other than weight ([actor resolution](/engine/actor-resolution.md)).
- Mood and combat expressions (`Mood*`, `CombatAnger`, `CombatShout`).
- Keeping panel weights after the actor unloads, or in saves.

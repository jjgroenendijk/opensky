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

The face does not jump to a new emotion. Each change moves a number of emotion points in a
number of seconds, both picked at random between their settings. The face then eases at that
speed, toward the new emotion and away from the old one, and back to nothing when the emotion
ends.

| Part | Settings | Vanilla |
| --- | --- | --- |
| Seconds per change | `fGameplaySpeakingEmotionMinChangeValue`, `...MaxChangeValue` | 1.5 |
| Points per change, out of 100 | `fGameplayiSpeakingEmotionMinDeltaChange`, `...MaxDeltaChange` | 100 |

So a vanilla emotion fades in over 1.5 seconds. `fGameplaySpeakingEmotionMaxChangeValue` is not
in `Skyrim.esm`.

[WARNING] The wiki gives these four settings no meaning or units. Seconds and emotion points are
OpenSky's reading of the names, not observed in the game.

### Blinks

A blink closes `BlinkLeft` and `BlinkRight` together over `fBlinkDownTime` (0.04 seconds) and
opens them over `fBlinkUpTime` (0.14 seconds). The next blink comes a random time after, between
`fBlinkDelayMin` and `fBlinkDelayMax` (0.5 to 2.5 seconds). Each face rolls its own times, so a
crowd does not blink together. The wiki gives these four settings their meaning and units.

### Eye movement

The eyes drift to a new point every `fAIHeadTrackPickNewOffsetTimer` seconds (2). The point is
random inside the range of the emotion the face shows:

| Emotion | Settings |
| --- | --- |
| Anger | `fEyeHeadingMinOffsetEmotionAngry`, `...Max...`, `fEyePitchMinOffsetEmotionAngry`, `...Max...` |
| Fear | the same, ending in `Fear` |
| Happy | the same, ending in `Happy` |
| Sad | the same, ending in `Sad` |
| Any other, or none | the same, ending in `Neutral` |

Vanilla heading ranges are about -0.05 to 0.1, and pitch ranges are smaller; a sad face looks
down. `fEyePitchMaxOffsetEmotionSad`, `fEyePitchMinOffsetEmotionAngry`, and
`fEyePitchMinOffsetEmotionHappy` are not in `Skyrim.esm` and keep the wiki values.

The drift drives the `LookLeft`, `LookRight`, `LookUp`, and `LookDown` targets of the
expression TRI. A full weight is a turn of `fTrackEyeXY` (28 degrees) to the side or
`fTrackEyeZ` (20 degrees) up or down. Positive heading looks left and positive pitch looks up.

[WARNING] OpenSky reads the offsets as radians: 0.1 radians is about 6 degrees, a small but
visible drift. Read as degrees they would not show. The pick timer, the sign, and the scale by
`fTrackEyeXY` and `fTrackEyeZ` are OpenSky's reading, not observed in the game.

The automatic weights are uploaded only when they change, so a still face costs nothing.

Source for every value: the Creation Kit wiki page "Category:Settings"
(<https://ck.uesp.net/wiki/Category:Settings>), read again from `Skyrim.esm`.

## Lip sync

A voice line's [lip track](/formats/lip.md) writes the lip layer. It drives the speech targets
and the blink, brow, look, and squint targets of the face, and it turns the head. Its blinks add
to the automatic blinks, clamped like any other weight. When the line ends the lip weights fade
out over 0.15 seconds.

## Settings

The launcher's Graphics page turns blinking, eye movement, dialogue expressions, and
[head tracking](/engine/head-tracking.md) on or off under Characters. Each switch writes one
persisted player setting, so a choice survives a restart.

## Failures

A TRI parse or pairing failure affects only that actor. The actor and its baked head still draw.
Any pair that worked still morphs.

## Not done yet

- Race sliders and character creation morphs.
- Body morphs other than weight ([actor resolution](/engine/actor-resolution.md)).
- Mood and combat expressions (`Mood*`, `CombatAnger`, `CombatShout`).

---
type: Subsystem
title: Lip sync
description: How a voice line's lip track drives one actor's FaceGen expression morphs on the
  audio clock, the fallback clock, and the release to the bind pose.
tags: [engine, dialogue, voice, lip-sync, facegen, audio]
---

# Lip sync

Every loaded actor with FaceGen expression targets has a lip sync player beside its face morph
player ([face morphs](face-morphs.md)). The track format is on the
[.lip](../formats/lip.md) page, and the voice container on the [.fuz](../formats/fuz.md) page.

## Starting a line

Starting a `.fuz` voice line decodes its `.lip` part, if there is one. The line goes to the speaker
of the open conversation, or else to the actor under the crosshair. That actor's player starts. It
never stops the audio.

Starting another line replaces the current one.

## The clock

The audio source is the clock. The audio engine publishes the source's elapsed time through a
small lock-protected clock. The render animation reads it at 30 Hz and maps the file's numbered
slots to named TRI targets.

If the source stops publishing, the line switches once to the render animation clock, anchored
at the line's original start. It does not switch back if a late audio time appears. Switching
back would make the mouth jump in the middle of a sentence.

## Weights

The face morph player keeps manual debug weights and lip weights apart. It adds them and clamps
the sum when it updates the actor's morph buffers. Turning lip sync off clears only the lip part.

When a line ends normally, the mouth does not hold its last shape. The last weights fade in a
straight line to the bind pose over 0.15 seconds.

## What is shown

The file stores numbered slots, not names. So the mapping is made visible. A snapshot shows the
actor, the line, which clock is in use, the track time, the live mapped weights, active slots
with no mapping, and whether the release fade is running.

## The game's lip clock

In the game the lips follow the frame time, not the audio. When a voiced line starts, the lip
track goes on the face at time 0, and the audio starts later:

- the delay is `fSpeechDelay` (0.1 s in `Skyrim.esm`) plus the track's lead, capped at 10 s;
- the lead is the track's negative start offset: a start of −N frames delays the audio by N/30 s.
  Vanilla tracks lead by 3 to 9 frames, mostly 5 (0.167 s).

So the mouth moves about 0.1 s before the authored timing. Each frame adds its frame time to the
track time; a long frame moves the lips by the whole frame. Nothing reads the audio position back,
so there is no resync. A frame that skips the actor's face update leaves the lips behind for the
rest of the line.

The track plays at 30 frames per second with no blend between frames: the frame shown is the
track time times 30, rounded down. A frame has 16 phoneme weights, and some tracks add a second
set of 17. After the last frame its weights hold until 0.2 s past the track's end. Then every
weight drops to 0 at once.

Example: a line with a 5-frame lead starts the lip track at 0 s and the audio at
0.1 + 5/30 = 0.267 s.

## How long a line lasts

- A line from the AI or a scene lasts while its audio plays, so its length is the start delay
  plus the audio. A scene dialogue action ends on the first update after the audio ends.
- A line from a script `Say`, or a response that plays a sound instead of a voice file, lasts the
  audio length plus `fGameplayVoiceFilePadding` (0.5 s), counted down in frame time. An unknown or
  zero audio length lasts 2 s.
- A talking activator or a plain reference with no voice file lasts `fSubtitleSpeechDelay` (8 s).

## What stops a line

The voice stops at once, with no fade, only when:

- the speaker drops out of full AI processing, as when it gets far from the player, its cell
  unloads, or it is disabled or deleted;
- the game interrupts the speaker's current speech on purpose.

These do not cut the audio: the end of a `Say` timer, the end of a scene dialogue action, or a new
action that starts while the speaker still talks. That action asks the speaker to finish and
waits for the audio to end.

A line is never started when the speaker is farther than the voice output model's maximum
distance from the listener on any one axis, a box rather than a sphere. Then the line has no
audio and no length. The player and the player's dialogue partner skip this test.

Voices close to the listener are made easier to hear. A dialogue voice within 250 units of the
listener counts as highlighted. While one plays, every other dialogue voice is turned down by 12
(probably decibels). The change takes 0.5 s, and a voice stays highlighted until 0.5 s before its
audio ends. These lower the volume only; they never stop a line.

## Where OpenSky differs

- The audio position drives the lips, and the audio starts with the lip track, with no
  `fSpeechDelay` and no lead.
- At the end the last weights fade to the bind pose over 0.15 s instead of holding for 0.2 s and
  dropping to 0.

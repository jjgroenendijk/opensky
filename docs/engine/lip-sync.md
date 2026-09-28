---
type: Subsystem
title: Lip sync
description: How a voice line's lip track drives one actor's FaceGen expression morphs on the
  audio clock, the fallback clock, and the release to the bind pose.
tags: [engine, dialogue, voice, lip-sync, facegen, audio]
---

# Lip sync

Every loaded actor with FaceGen expression targets has a lip sync player beside its face morph
player ([face morphs](/engine/face-morphs.md)). The track format is on the
[.lip](/formats/lip.md) page, and the voice container on the [.fuz](/formats/fuz.md) page.

## Starting a line

Starting a `.fuz` voice line decodes its `.lip` part, if there is one. The line goes to the
speaker of the open conversation, or else to the actor under the crosshair. That actor's player
starts. Missing lip data, no chosen actor, or bad input is logged and shown in the panel. It never
stops the audio.

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

## Controls

World > Dialogue & Voice > Voice: pick a voice file, play it, and turn lip sync on or off. The
readouts show the voice line, the voice submix (distance and playback clock, or silence), and the
lip sync snapshot.

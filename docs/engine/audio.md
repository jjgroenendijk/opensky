---
type: Subsystem
title: World audio playback
description: The AVAudioEngine graph with positional sources and category submixes, how gain,
  mute, and solo combine, world to listener coordinates, threading, the source budget, gain
  ramps, and the per-frame cost.
tags: [engine, audio, playback, spatial]
---

# World audio playback

The audio engine turns decoded sound files into positioned, audible sound. How each file type is
decoded, and the voice route, are on the [audio decoding](/engine/audio-decoding.md) page. The
things that start sounds are [world sound effects](/engine/world-sfx.md),
[music](/engine/music.md), and [footstep sounds](/engine/footstep-sounds.md).

## The graph

There is one `AVAudioEngine` per app. It is created the first time audio is enabled.

```text
positional AVAudioPlayerNode (mono, one per source)
    --> AVAudioEnvironmentNode --> main mixer --> output device
non-positional AVAudioPlayerNode (stereo, one per source)
    --> category submix AVAudioMixerNode (effects/voice/music/footsteps) --->--/
```

- The environment node does the 3D mixing. Its inputs must be mono: it passes stereo through
  without placing it. So stereo sources are mixed down to mono by averaging the channels.
- Each positional source uses `.equalPowerPanning`. It is fixed and cheap, which the offline render
  tests need.
- The category submixes carry sources with no world position, such as music and ambience. Such a
  source keeps its own channel layout and connects straight to its submix. It gets no panning, no
  distance fade, and no position. A positional source cannot go through a submix, because each
  needs its own environment input. So it carries its category factor on its own player node.
- Routing is set by the call that starts the source, not guessed from the category.

## Gain

```text
effective gain = master x category x source x fade
```

Master is the main mixer's output volume. Fade is the ramp factor below. The category factor is
applied exactly once: on the player node for a positional source, and on the submix for the
others. Applying it at both would square it. Distance fading comes after all of this, and only for
positional sources.

Mute and solo are two more filters inside the category factor. One function gives the category's
volume when it is audible, and zero when it is muted or another category is soloed. The submix
volumes, the player node volumes, and the panel's gain column all read that one function, so they
cannot disagree. Changing a filter applies it again to sources that are already playing.

- Mute and solo are separate filters, and both must pass. Soloing a muted category leaves it
  silent. Only unmuting makes it audible.
- Mute is separate from the volume. Unmuting restores the slider level, not full volume.
- Solo is one optional category, so only one can be soloed at a time.

The engine starts with the game, unless the Sound setting is off
([settings](/engine/settings.md)). A start failure, such as no output device, is shown in the readout.
It never crashes and never blocks rendering.

The four categories are the four vanilla `SNCT` nodes marked for menu display: Effects, Voice,
Music, and Footsteps ([sound records](/formats/sound.md)). A world sound follows `SNDR` `GNAM` to
`SNCT` `PNAM` to one of them. Missing or broken data falls back to Effects.

## World to listener coordinates

The world is right-handed and Z-up, in native units: +X east, +Y north, +Z up, and 1 unit is
0.0142875 m ([coordinates](/decisions/coordinates.md)). The listener space of
`AVAudioEnvironmentNode` is right-handed and Y-up, and its distance settings use the position
unit, which OpenSky sets to meters.

| World (Z-up, units) | Listener (Y-up, meters) |
| --- | --- |
| Position `(x, y, z)` | `(x, z, -y) * 0.0142875` |
| Direction `(x, y, z)` | `(x, z, -y)`, no scale |
| +X east | +X |
| +Y north | -Z, straight ahead of a default listener |
| +Z up | +Y |

This is the same basis change the renderer uses. The listener faces
`(cos yaw * cos pitch, sin yaw * cos pitch, sin pitch)`, with its matching up vector, both mapped
as directions. Example: facing +X, a source at world -Y is on the listener's right, and renders
louder in the right channel.

## Threading

Three places run code, with one crossing each:

1. The main actor owns the graph, volumes, source list, and listener pose. Each frame, the renderer
   pushes the camera pose and runs retirement and purge. It is skipped while the world is paused.
2. One serial decode queue owns each source's decoder, which is not `Sendable`. It decodes chunks
   of 16 packets (about 0.75 s) into PCM buffers and keeps at most 3 scheduled ahead. So a music
   track is never decoded whole (about 37 MB of PCM). Buffer completion handlers run on an AVFAudio
   queue and hop straight back to the decode queue.
3. The audio render thread runs no OpenSky code. `AVAudioPlayerNode` reads the scheduled buffers
   there itself. Nothing from OpenSky allocates, locks, or logs on it.

Main to queue is a start or stop request, with no waiting. Queue to main is one locked "finished"
flag the tick checks. Engine to panel is a snapshot value read twice a second. The main actor never
waits for the decode queue.

## Budget and cleanup

- At most 8 positional sources play at once. The limit is provisional.
- Starting a positional source at the limit stops the oldest one first. It is predictable and fits
  how short effects end anyway. A priority scheme waits for game data.
- Non-positional sources are outside the limit and the cell purge. A burst of effects never stops
  the music, and streaming never stops it either: it has no cell. Only an explicit stop, a finished
  fade-out, a stream that cannot be used, or engine shutdown ends one.
- A source that played its last buffer sets its finished flag, and the next tick removes it.
- A looping source, such as an ambience bed, rewinds to its first packet at the end of the file
  and keeps going. It never sets the finished flag. A pass that decoded no audio ends the source
  instead of rewinding, so a file the decoder cannot use cannot spin the decode queue.
- Each positional source remembers the exterior cell of its position. The tick stops sources more
  than 3 rings from the listener's cell, one ring past the 5x5 loaded grid.

## Gain ramps

Every source has a fade gain from 0 to 1, multiplied into its node volume. A ramp has a start
gain, a target, a duration in seconds, and elapsed time. This is the crossfade tool.

- Ramps advance only by the frame time the tick passes in. No wall clock is read. The renderer
  skips the tick while the world is paused, so a crossfade freezes in menu mode and does not jump
  on resume.
- The curve is linear in amplitude, not decibels. It is simple and fine for music crossfades.
- A new ramp during a ramp replaces it, starting from the current gain. So the level never jumps.
  A duration of zero or less applies the target at once.
- "Fade out and stop" ramps to silence and removes the source at the end.
- A ramp within 1 ms of its duration counts as done and snaps to the target. Adding frame times in
  `Float` never sums exactly (60 additions of 1/60 do not make 1). Without this, a fade-out could
  stay just above silence and never end.
- The fade is part of the same volume product, so moving a slider during a crossfade applies the
  ramp again instead of overwriting it.

## Distance

Distance fading is provisional: the inverse model, reference distance 2 m, maximum distance 60 m
(about one exterior cell), and rolloff 1. The game's own values come from `SNDR` and `SDSC`. These
exist so the panel is clearly distance-dependent.

## Per-frame cost

The only per-frame audio work on the main thread is one update: push the camera pose, run the tick
(ramps, retirement, purge), and tick the music director. Decoding never runs there, and the render
thread runs no OpenSky code. The work is bounded by the 8-source limit: a few scalar updates per
source, with no allocation, no file reads, and no decoding.

The budget is 0.5 ms for both the mean and the p95 of this update, about 1.5% of a 33.33 ms frame.
Both `bench --fly-path` and `bench --walk-path` attach an audio engine so the tick really runs, and
print an `audio update:` line. The measured floor, with no live sources, is about 35 times under
the p95 limit. The rest grows with live sources, which the limit caps at 8. So the budget is
reasoned headroom over a measured floor. A frame that does no audio work records zero.

## Controls

World > Audio has five sections: Output, Sources, Voice, Footsteps, SFX & Ambience, and Music.

- Output: Enabled, master volume, a volume slider per category, and per category a mute and a
  solo checkbox. Solo is a checkbox, not a radio group, because clicking the soloed category again
  clears solo, which a radio group cannot do. A muted or soloed category counts as a change, so the
  sidebar dot lights and the reset clears both. The readout ends with a line like
  `Mute: Effects, Music  Solo: Voice`, or `Mute: none  Solo: none`.
- Sources: pick an `.xwm` file and play it, or stop all. The file plays 700 units (about 10 m)
  ahead of the camera as an effect, so turning or strafing pans it at once. The readout lists live
  sources with file, category, position, distance, gain, and playback time. The time reads `--`
  until the source renders its first buffer, which is a real state, not zero.

A manual check: turn on audio, play any `music\...` file, then turn and strafe. The sound must pan
between ears as it passes the view axis, and fade as you fly away. Mute Effects and check that the
effect goes silent while music plays. Solo Music and check that everything else stops. Reset, and
check that the mix returns.

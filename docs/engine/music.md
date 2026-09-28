---
type: Subsystem
title: Music playlists
description: How a music type is chosen for the current cell, the exploration, town, interior,
  and combat states, playlist order and flags, finding the shipped file, and crossfades.
tags: [engine, audio, music, playlists]
---

# Music playlists

The music system turns the [music records](/formats/music.md) into music that follows the
streamed world. It has two parts, like [world sound effects](/engine/world-sfx.md):

- a selection step with no audio device, which picks a playlist from a context;
- a music director on the main actor, which owns the playing sources.

Playback and gain ramps are on the [world audio](/engine/audio.md) page.

## Choosing a music type

Selection checks three links, most specific first, and takes the first that names a `MUSC` the
store has:

```text
CELL XCMO  ->  REGN RDMO (the first that resolves, among the cell's XCLR regions)
           ->  WRLD ZNAM
```

A link to a missing record is skipped. It does not mean "no music", so a broken override in a
mod cannot silence the world. Regions are checked in the cell's `XCLR` order, so the choice is
the same every time when two regions both have an `RDMO`. With nothing to select (no music data,
no link, or a playlist with no playable track) the result is silence, and the director stops.

Cell streaming builds a music key from the center cell and sends it only when it changes. So a
frame with no change costs one comparison. It is sent from the same places as the ambience
context: each frame for an exterior move, and on entering or leaving an interior. Entering an
interior clears the old key first, so an interior entered twice still sends it.

## The states

Only one state is written anywhere in the records, so the others are derived:

| State | Derived from | Limits |
| --- | --- | --- |
| Interior | An interior scene is loaded | Wins over all others. An interior with a town playlist is still "interior" |
| Town | An exterior whose `MUSC` editor ID starts with `MUSTown`, ignoring case | A naming rule, not data. A renamed record, or one with no `EDID`, reads as exploration |
| Exploration | Every other exterior, also one with no playlist | The fallback. It does not prove an exploration playlist exists |
| Combat | The combat loop says so | Not derived from the cell. See below |

Combat does not come from the cell. When combat starts, the director selects the first `MUSC`
whose editor ID starts with `MUSCombat` (ignoring case), found by FormID so the choice is the
same every run. It remembers the selection it interrupted. When combat ends, it returns to
exactly that selection, without selecting again. So a fight that started in a town ends with the
town's playlist. A cell crossed during the fight changes what combat will return to, but does not
interrupt the fight music. A load order with no combat playlist keeps the current music and says
why. The `MUSCombat` prefix has the same limits as the town prefix. See
[combat](/engine/combat.md).

There is no dungeon state. Vanilla has `MUSDungeon...` records, but game systems OpenSky does not
have yet start them. Adding a state for them now would be a guess.

## Playlists

The winning `MUSC` gives an ordered list of playable tracks.

A `MUST` whose `CNAM` is the palette type has `SNAM` children instead of an `ANAM` file. It is a
nested playlist. Nesting is expanded at most 4 levels deep, with a set of visited records. So a
palette that names itself stops instead of looping.

Silent tracks, which have no `ANAM`, and tracks whose file name breaks the `music\` path rules are
dropped. The rest keep their order. A playlist that loses every track gives silence, but the
readout still names the `MUSC`. Whether the file exists is not checked here, because selection
reads no files. A missing file fails later, when it loads.

Order:

- `Maintain Track Order` (`0x0008`) keeps the `TNAM` order.
- Without it, the order is a fixed shuffle. It is a Fisher-Yates shuffle with SplitMix64,
  seeded by an FNV-1a hash of the interior flag, the three links, and the cell. Swift's `Hasher`
  is not used, because it is seeded per process, so two runs of the same scene would differ.

What happens at the end of a track:

- `Plays One Selection` (`0x0001`): play one track, then silence.
- `Cycle Tracks` (`0x0004`): go through the list and start again at the end.
- Neither flag: repeat the one track while the selection stays the same. That is how a
  single-track `MUSC` behaves.

`Ducks Current Track`, `Does Not Queue`, and the `MUSC` priority are decoded but not used. They
matter only when two playlists can play at once.

## Finding the shipped file

A music path is the name the record gives, normalized
([path resolution](/formats/music.md#music-paths)). On the shipped install, that name is not
a file that exists. This is observed, not documented: all 242 distinct `MUST` `ANAM` and `BNAM`
names in `Skyrim.esm` end in `.wav`, but all 269 archive entries under `music\` are `.xwm`.
Vanilla `SNDR` sounds are the other way: they really are `.wav`, and need no rule.

So loading a track tries, in order:

1. the path exactly as written;
2. the same folder and stem with the extension `.xwm`, only if step 1 failed and the written name
   has an extension that is not `.xwm`.

A track missing under both names reports the error from the written path. So a missing file is
reported as missing, not as a wrong extension.

This rule sits where the file loads, not in the path normalizing step. Normalizing is a pure
string change. It cannot tell a name that exists from one that does not, so changing the
extension there would guess for every track, including mod tracks that really are `.wav`. The
playing source is named after the file that loaded, so the readout shows the real file.

## Crossfades

A crossfade starts the new source at zero gain, fades the old source to silence and stops it,
and fades the new source up over the same time. Both fades move only with the renderer's frame
time, which is zero while paused. So a crossfade freezes in menu mode instead of skipping ahead.

The new selection sets the duration:

- `MUSC` `WNAM`, in seconds, when present;
- 2 seconds when not;
- zero with `Abrupt Transition` (`0x0002`). Both ends apply at once.

Turning music off with the toggle stops at once instead of fading. A context that resolves to
silence still fades out over 2 seconds.

## Lifetime

Music sources have no position. The engine leaves them out of the source budget and the cell
purge. So the director alone stops them.

The director follows the same rules as the sound effects director:

- The wanted selection is kept whether it plays or not. A context that arrives while music is off
  is not lost, and turning music on starts it at once.
- A context change, a forced playlist, and the toggle all take one path, so they cannot drift
  apart.
- The readout comes from the live sources. It cannot claim music that already stopped.

The next track starts from the per-frame tick. The audio engine removes a stream that reached
its end, and the director notices this in the same frame. Sources fading out in a crossfade are
tracked apart, so a fading track that ends is not mistaken for the current one. A repeating
selection asks the engine to loop, so it never reaches this step.

## Failures

Nothing throws to the caller. Each failure gives silence plus a reason in the readout:

- no music data: silence, no error;
- a link that does not resolve: the chain goes on;
- a playlist with no playable track: silence, and the `MUSC` is still named;
- a track whose file does not load: it is skipped for the next one, at most once per track. If
  every track fails, silence, with the last load error;
- the audio engine is not running: the selection is kept and starts when the engine does.

## Controls

World > Audio > Music:

- Music enabled. Off fades out the current track. On starts the last selection again.
- Music type: "None (automatic)" and every `MUSC` editor ID. Choosing one crossfades to it, past
  the selection chain. Choosing "None (automatic)" drops the forced type and stops music, so the
  next cell selects through the chain again.
- Stop music, for comparing with silence.
- Readout: the state, the playlist and file, and an error line when there is one.

Nothing plays until World > Audio > Output > Enabled is on.

A manual check: walk an exterior cell and hear the exploration playlist. Enter a city and hear the
crossfade to its town playlist. Enter an interior and check the state readout.

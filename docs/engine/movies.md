---
type: Subsystem
title: Movies
description: How OpenSky plays Bink movies - the startup logo before the main menu and Papyrus
  Game.PlayBink - across the decoder, the menu stack, the renderer, and the audio engine.
tags: [engine, movie, bink, menus, rendering, audio]
---

# Movies

The game plays a Bink movie in two places: the Bethesda logo, `BGS_Logo.bik`, before the main
menu, and any movie a script starts with
[`Game.PlayBink`](https://ck.uesp.net/wiki/PlayBink_-_Game). The file layout is in
[Bink](/formats/bink.md).

## How a movie plays

1. The movie player opens a menu named `BinkMovie` that pauses the world. The CK wiki says the
   game, Papyrus included, is frozen while a movie plays; the paused world gives the same result.
   The name is OpenSky's own: the game plays movies outside its Scaleform menus.
2. One `@concurrent` load reads the file, frames it, and decodes the whole sound track to PCM. The
   logo's sound is about 7 seconds, so a whole-track decode costs little memory.
3. The video decodes on the shared asset load queue. A Bink frame builds on the one before it, so
   the decoder decodes every frame in order, and stays 3 frames ahead of the frame due.
4. The clock starts when the first picture is ready. The sound starts on the same frame.
5. Each frame shows the newest decoded picture that is due. When the decode falls behind, the
   picture holds and then jumps forward; the sound never waits.
6. After the last frame's time, or a skip, the menu closes and the waiting caller continues: the
   title menu opens, or the `Game.PlayBink` call returns.

## Drawing

The renderer draws the picture after the menus and before the developer UI, so it covers
everything. The three planes upload as 8-bit textures, one set per frame in flight, so an upload
never changes a texture the GPU still reads. The shader turns YCbCr into RGB with the BT.601
matrix and turns the result into linear colour for the sRGB target.

[WARNING] No source says which matrix Bink uses. BT.601 matches libavcodec's default for this
decoder.

A letterboxed movie keeps its aspect ratio and draws black bars. With `abLetterbox` false the
picture stretches over the whole frame.

## Sound

The sound plays as a non-positional source in the effects category. `abMuteAudio` mutes the voice
and footstep categories while the movie plays, and `abMuteMusic` mutes music. Each category comes
back when the movie ends, unless it was muted before.

## Skipping

An interruptible movie ends on the menu cancel or accept key. The startup logo is interruptible.
`openskycli game debug skipbink` ends any movie.

## Where OpenSky differs

- [WARNING] Not confirmed which keys skip a movie in the game, or that the logo can be skipped.
- [WARNING] Not confirmed which sound categories "game audio" covers. OpenSky keeps the effects
  category on, because the movie's own sound plays in it.
- A slow decode drops pictures but keeps the sound on time. The game's player is not documented.

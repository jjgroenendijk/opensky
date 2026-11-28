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
[Bink](../formats/bink.md).

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

The game asks the Bink library for RGB pictures and passes no matrix or range. In the reference
game on 2026-11-15, a script-played `BGS_Logo.bik` was captured and compared with libavcodec
decodes of the same moment (`.logs/bink-check/`, local only). Studio levels widened to full range
matched with a mean squared error of 4.9 per channel; full levels gave 246. The logo is grey, so
BT.601 and BT.709 differ by less than 0.1 there, and no vanilla movie tells the two apart. OpenSky
keeps BT.601, libavcodec's default for this decoder.

The game draws the decoded RGB picture as it is. The frame goes into 256 by 256 tiles of plain
8-bit textures, not sRGB textures, and a pass-through shader draws them straight to the screen
after a clear. No gamma step, brightness, contrast, tint, image space, or HDR tone mapping
touches it. So a frame on screen has the colours of the decoded file: in the reference game the
logo's mean colour was 149, 154, 157 against 150, 154, 159 in a standard decode.

With `abLetterbox` true the movie fits the screen width and is centred from top to bottom. With
it false the movie fits the screen height and is centred from side to side.

## Sound

The movie's sound plays at the file's own level. No volume slider, category, or mute changes it,
the master volume included. In the reference game the logo's sound matched the file's samples
with a gain of 1.00.

`abMuteAudio` pauses the master sound category while the movie plays, the same pause a menu
uses, with a fade time of 0. Each sound in that category, or in a category below it, pauses at
once, if it can pause. A sound that cannot pause keeps playing 40 dB quieter. A sound with no
category plays on. A sound that starts during the movie starts 40 dB quieter. When the movie
ends, the category is un-paused, again with a fade time of 0, so the sounds come back at once.

The game runs the movie in its own loop, so the world does not update until it ends.

`abMuteMusic` pauses the music: the playing track fades out over 500 ms and ends, and the music
type stays the current one. When the movie ends, the type plays its tracks again. Pauses nest, so
the music returns only when every pause has ended. Audio comes back first, then music. Both flags
default to true ([PlayBink - Game](https://ck.uesp.net/wiki/PlayBink_-_Game)), and the startup
movies use both.

With both flags false, a movie changes no other sound. Nothing lowers the other sound by a fixed
amount while a movie plays.

[WARNING] The reference game did not show the muting when the bridge called `Game.PlayBink`: the
tavern's sound under the logo stayed about 2 dB below its level before, with the default flags
and with every flag false, and the music system reported the same track playing. The bridge
calls the function from outside a running script, which may take another path.

## Skipping

An interruptible movie ends on a new press of Activate: E on the keyboard and A on a gamepad, or
the key the player bound to it. A press that started before the movie does not count. Escape,
other keys, and mouse buttons do not skip, unless the player bound them to Activate. Closing
the window ends any movie.

The startup movies are a comma-separated list. Each one is interruptible, and a skip while the
game still loads in the background ends the rest of the list. A movie that is not interruptible
plays to its last frame. `openskycli game debug skipbink` ends any movie.

## Where OpenSky differs

- A slow decode drops pictures but keeps the sound on time. The game's player is not documented.
- OpenSky turns the picture into linear colour for its sRGB target. Beside the game, its logo
  frame was about 40 % darker (mean 91, 92, 101), as if a gamma step were applied twice.
- With `abLetterbox` false OpenSky stretches the picture over the whole frame.
- During a movie OpenSky lowers the other sound categories to about 1 % but does not pause them,
  and it fades them over 100 ms.

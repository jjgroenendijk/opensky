---
type: Subsystem
title: Audio decoding and voice
description: How xWMA and WAV files reach the audio graph, the extradata policy for vanilla
  xWMA, the .fuz voice route, and the playback clock and line-finished signal.
tags: [engine, audio, xwm, wav, fuz, voice]
---

# Audio decoding and voice

This page covers how each kind of vanilla audio file reaches the
[audio graph](/engine/audio.md). Music and voice are xWMA. Every sound effect is a plain WAV file.

## xWMA

Music and voice stream through the WMA decoder ([ffmpeg audio](/decisions/ffmpeg-audio.md)). The
container is on the [.xwm](/formats/xwm.md) page.

Vanilla `.xwm` files have `cbSize == 0`, so the container gives the decoder empty extradata. But
ffmpeg's WMAv2 decoder reads stream flags from extradata. So empty extradata is replaced with the
six-byte block that ffmpeg's own xWMA demuxer builds: byte 4 is 31, and the rest are zero
(`libavformat/xwma.c`). The container parser does not own this rule. The audio engine does.

`openskycli audio sweep` decodes all 269 vanilla xWMA files, each to exactly the frame count its
`dpds` table declares.

## WAV

Every sound effect in the install, all 5,978, is a RIFF/WAVE file of uncompressed linear PCM
([.wav](/formats/wav.md)). Playing a file checks the RIFF form type at byte 8:

- `XWMA` streams through the decoder.
- `WAVE` is read whole into one PCM buffer and scheduled once.

An effect lasts a fraction of a second. A footstep file is about 26 KB. Streaming it would add a
queue hop and three buffers of lookahead for nothing. A buffer source removes itself through its
completion handler, so it is cleaned up in the frame it ends, not left for the source limit.

## Voice

A dialogue line is a [.fuz](/formats/fuz.md) file: a lip sync block followed by a complete xWMA
file. Playing a voice line frames the container and sends the xWMA part down the same positional
streaming path as an effect, in the Voice category. The streamer never needed a second container
type, because the payload is a whole `.xwm` file at an offset.

The call returns the source ID, the duration from the `dpds` table, and the untouched lip bytes
for [lip sync](/engine/lip-sync.md). A broken container throws before any source starts, so a line
that cannot be framed is a reported miss, not a silent player.

Vanilla voice is mono 44.1 kHz, which is what the positional path needs. So the mono mix-down used
for music never applies to a line.

Choosing which file to play belongs to the records, not the engine. The path is built from the
`INFO` and the speaker's voice type. The naming rule is on the [.fuz](/formats/fuz.md) page.

## Playback clock

The engine reports how far into its material a source has played, in seconds, or nothing if no
source has that ID or nothing has rendered yet. It keeps one clock that only grows. Each source
remembers the clock value when it started, and its position is the difference.

`AVAudioPlayerNode.playerTime(forNodeTime:)` was tried first. It hangs the app-hosted test host
under offline manual rendering, every time ([environment](/tools/environment.md)). Subtraction
cannot block, which is a second reason to prefer it.

The clock has two sources, both in seconds:

- Offline, it is `engine.manualRenderingSampleTime / sampleRate`. It moves by exactly the frames
  each offline render produced. So a test can turn a rendered frame count straight into an expected
  time.
- Live, it adds up the audio tick's frame time, the same time the gain ramps use. So it freezes in
  menu mode instead of jumping on resume.

The cost: this is time since the source started, not the sample position that reached the output.
A streamed source whose first chunk is still decoding reads a few milliseconds ahead of what is
heard. Subtitles and lip sync want time into the line, so this is the right number for them.

## Line finished

The engine reports a source's ID once the source has played to its end and been removed. It is
reported from one place only, so it means "played out". A source stopped by hand, evicted by the
source limit, or purged with its cell does not report. That is the point: a subtitle must clear
when the line ends, not when it is cut off.

## Voice controls

World > Dialogue & Voice > Voice has a filter field, a file picker, and Play line. The archives hold
75,408 voice files, so the picker lists the first 200 matches of the filter, and the readout always
says how many matched in total. A short list that looked like the whole set would mislead. The
filter starts with a voice type folder, so the picker is useful before anything is typed. Play line
starts the file the same way a conversation does: framed as `.fuz`, positional, ahead of the
camera, in the Voice category. The readout shows the line, its duration and lip byte count, and the
playback position.

`openskycli audio voice-sweep` frames every `.fuz` entry and checks that every voice file name can
be rebuilt from the records.

---
type: File Format
title: Bink movie (.bik)
description: Layout of the Bink 1 movie container Skyrim SE plays from Data/Video - the header,
  the audio track tables, the frame index, and the packets of one frame - and how OpenSky decodes it.
tags: [format, video, audio, bink, movie]
---

# Bink movie (.bik)

Skyrim SE plays its few movies, such as the startup logo `BGS_Logo.bik`, from Bink 1 files
in `Data\Video`. A `.bik` file is a container: a header, tables for the audio tracks, a frame
index, and then the frames. OpenSky reads the container itself and hands each packet to
libavcodec, which holds the Bink video and audio decoders
([ffmpeg decision](/decisions/ffmpeg-audio.md)). The player is in [movies](/engine/movies.md).

## References

No Bethesda or RAD Game Tools code was used.

- MultimediaWiki, [Bink Container](https://wiki.multimedia.cx/index.php/Bink_Container),
  written from Mike Melanson's description of the format.
- FFmpeg 9.0.2 `libavformat/bink.c` (LGPL), read as documentation for the field order and for
  what the decoders expect as private data. OpenSky does not link `libavformat`.
- The vanilla `BGS_Logo.bik`, read by `BinkMovie` and decoded by the movie player.

All integers are little-endian.

## Header

| Offset | Size | Field |
| --- | --- | --- |
| 0 | 4 | Tag: `BIK` and a revision letter, such as `BIKi`. `KB2` starts a Bink 2 file |
| 4 | 4 | File size minus 8 |
| 8 | 4 | Frame count |
| 12 | 4 | Largest frame size in bytes |
| 16 | 4 | Frame count again |
| 20 | 4 | Width |
| 24 | 4 | Height |
| 28 | 4 | Frame rate numerator |
| 32 | 4 | Frame rate denominator |
| 36 | 4 | Video flags |
| 40 | 4 | Audio track count |

Revision `k` adds 4 more bytes here. Their meaning is not published, so OpenSky skips them.

OpenSky declines Bink 2, which needs a decoder libavcodec does not have. It also throws on a
frame count of 0 or above 1,000,000, a side of 0 or above 32,767, a zero rate, or more than
256 audio tracks.

## Audio tracks

Three tables follow, each with one entry per track, in this order:

1. A 4-byte largest decoded packet size. OpenSky does not need it.
2. A 2-byte sample rate, then a 2-byte flags word. Bit 13 means stereo; bit 12 means the DCT
   codec, else the RDFT one.
3. A 4-byte track ID.

## Frame index

The index holds one 4-byte entry per frame and one more entry: the end of the last frame.
Bit 0 of an entry marks a keyframe; the rest is the frame's offset in the file. A frame runs
from its offset to the next entry's offset. Offsets are even, so a frame of odd size ends with
one pad byte, which the reader passes on as part of the video packet.

## Frame packets

Each frame holds one audio packet per track, in track order, and then the video packet:

- An audio packet is a 4-byte size and that many bytes. The packet starts with a 4-byte
  sample count, so a packet under 4 bytes holds no sound. The decoder reads the count itself.
- The video packet is the rest of the frame.

## Decoder setup

libavcodec needs the container fields as codec parameters:

- Video (`AV_CODEC_ID_BINKVIDEO`): `codec_tag` is the 4-byte tag, the private data is the
  4-byte video flags, and width and height come from the header. The decoder gives YUV 4:2:0,
  or 4:2:0 with alpha. Revision `k` gives full-range levels; older ones give studio levels.
- Audio (`AV_CODEC_ID_BINKAUDIO_DCT` or `_RDFT`): the sample rate and channel count come from the
  track table, and the private data is the 4-byte tag, because the decoder reads the revision
  letter from it.

## Confirmed on the install

`BGS_Logo.bik` is `BIKi`, 166 frames of 1920 x 1080 at 24000/1001 frames per second, with
video flags 0. It has two audio tracks, both 48 kHz stereo DCT (flags `0x7000`), with IDs 1 and
0 in that order. Every frame frames cleanly and decodes in libavcodec.

[WARNING] No source says which track the game plays when a movie has two. OpenSky plays the
track with ID 0.

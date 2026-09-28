---
type: File Format
title: FUZE voice container (.fuz)
description: Layout of Skyrim SE .fuz voice files (FUZE header, optional .lip data, xWMA
  audio), and the voice file naming rule found from the vanilla archive.
tags: [format, audio, voice, dialogue, xwma]
---

# FUZE voice container (.fuz)

Every spoken dialogue line in Skyrim SE is a `.fuz` file. It is a simple container that
joins one `.lip` lip-sync blob and one `.xwm` audio file, so the game opens one file per
line. The parser only splits the two parts. The audio goes to the
[xWMA parser](/formats/xwm.md) and then the [ffmpeg WMA decoder](/decisions/ffmpeg-audio.md).
The lip data goes to the [LIP decoder](/formats/lip.md).

Sources (no Bethesda code):

- xEdit `dev-4.1.6`
  [`Core/wbDataFormatMisc.pas`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDataFormatMisc.pas),
  read as documentation. Its `dfFUZ` definition gives the layout: `FUZE` magic, a uint32
  `Version` with default `1`, a uint32 `LIP Size`, the `LIP Data`, and the rest of the file
  as `XWM Data`.
- Creation Kit wiki,
  [How to generate voice files by batch](https://ck.uesp.net/wiki/How_to_generate_voice_files_by_batch).
  The official pipeline writes a `.lip` with the Creation Kit, a `.xwm` with `xWMAEncode`,
  and joins them into a `.fuz`. The page also gives the folder part of the voice path.
- The real install, through `openskycli audio info` and `openskycli audio voice-sweep`. The
  file-name rule below was found from the real files, because no published description
  matches them.

## Layout

All integers are little-endian.

| Offset | Type | Field | Notes |
| --- | --- | --- | --- |
| 0x00 | char4 | Magic | `FUZE` |
| 0x04 | uint32 | Version | `1` in all vanilla files |
| 0x08 | uint32 | LIP Size | Bytes of lip data. Can be 0 |
| 0x0C | bytes | LIP Data | The `.lip` file, unchanged |
| 0x0C + size | bytes | XWM Data | A complete RIFF/XWMA file, to the end |

The audio has no length field and there is no trailer. The audio is a whole `.xwm` file, so
the xWMA parser reads it as it is. Here is a vanilla line at the boundary: the header, 1728
bytes of lip data (`0x6C0`), then `RIFF`:

```text
00000000  46 55 5a 45 01 00 00 00  c0 06 00 00 01 00 00 00   FUZE............
000006cc  52 49 46 46 f4 28 00 00  58 57 4d 41 66 6d 74 20   RIFF.(..XWMAfmt
```

A `LIP Size` of 0 is legal. An `INFO` with the "no LIP file" flag ships a line with no lip
data.

## Errors

A wrong magic, a short header, or a `LIP Size` that reaches past the end or leaves no audio
is malformed. A version other than 1 is unsupported. `LIP Size` is widened to `Int` before
any math, so a huge value is rejected instead of overflowing.

Audio that is not valid xWMA fails in the xWMA parser, as a separate step. So a report can
tell container errors apart from audio errors.

## Where a voice file lives

```text
sound\voice\<plugin file name>\<voice type editor ID>\<name>.fuz
```

The plugin is the one that defines the `INFO`. In vanilla that is `skyrim.esm`,
`dawnguard.esm`, `hearthfires.esm`, or `dragonborn.esm`. The voice type is the editor ID of
the `VTYP`. So the same line exists once per voice type. All vanilla voice files are in
`Skyrim - Voices_en0.bsa`.

## The file-name rule

```text
<quest editor ID>_<topic editor ID>_<8 hex FormID>_<response number>.fuz
```

- Quest: the editor ID of the `QUST` in the owning `DIAL`'s `QNAM`.
- Topic: the editor ID of that `DIAL`. It is often empty, which gives a double underscore.
- FormID: the `INFO` FormID as the exporting plugin numbered it. The Creation Kit does not
  know the load order. So the plugin's own records use index `00`, and a master's records use
  that master's position in the master list. Every Dawnguard line is `00xxxxxx`. The few that
  override an `Update.esm` record are `01xxxxxx`.
- Response number: the one-based response number from `TRDT`. It gives `_1`, `_2` for a line
  said in parts.

The quest and topic share a budget of 25 characters:

1. The topic reserves at most 15 characters.
2. The quest is written in full if it fits in what is left of the 25. Otherwise it is cut to
   10 characters.
3. The topic then takes what the quest left, up to its own length.

Examples:

- `CWMission04` (11) stays whole next to `CWPrisonerWait` (14). Together they are exactly 25.
- `BardSongs` (9) leaves 16 characters, so the topic can use 16, not only 15.
- `BYOHHouseDialogueHousecarl` (26) becomes `byohhoused`, even with an empty topic.

Names are lowercase, like every VFS key.

## How the rule was found

Community descriptions of this rule disagree with each other and with the shipped files. So
the archive was the authority. `openskycli audio voice-sweep` builds a name for every `INFO`
response in every plugin and compares it with the archive listing. It prints every mismatch
next to the editor IDs that produced it. The rule above is what survives.

The rule reproduces about 99% of the vanilla names. The rest are Bethesda's mistakes, and no
correct rule can reach them:

- Spelled differently. A line was exported, then the quest or topic was renamed, and the file
  kept the old name. Example: some Companions lines are still named `c03_c03eorlund...`, but
  the records now say `C00`. Two names are simply broken: one has a space, and one is two
  names joined.
- No matching response. The file outlived its record. The `INFO` was removed or renumbered
  after export.

OpenSky does not scan the archive for a close match. A line that does not resolve is reported
as a miss.

## Vanilla facts

- Every file is version 1 with 44.1 kHz WMAv2 audio. Almost all are mono. A few hundred are
  stereo.
- Most lines have lip data. About 2% do not.

---
type: File Format
title: FUZE voice container (.fuz)
description: Layout of Skyrim SE .fuz voice files - the FUZE header, the optional .lip data,
  the xWMA audio - and the voice file naming rule found from the vanilla archive.
tags: [format, audio, voice, dialogue, xwma]
---

# FUZE voice container (.fuz)

Every spoken line of Skyrim SE dialogue is a `.fuz` file. It is a simple container that
joins one `.lip` lip-sync block and one `.xwm` audio stream, so the game opens one file per
line. The audio goes to the [xWMA parser](/formats/xwm.md) and the
[WMA decoder](/decisions/ffmpeg-audio.md). The lip data goes to the [LIP parser](/formats/lip.md).

## References

No Bethesda code was used.

- [xEdit `dev-4.1.6` `Core/wbDataFormatMisc.pas`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDataFormatMisc.pas),
  read as documentation. Its `dfFUZ` definition gives the layout: a `FUZE` magic, a uint32
  `Version` with default `1`, a uint32 `LIP Size`, `LIP Size` bytes of `LIP Data`, and the
  rest of the file as `XWM Data`.
- Creation Kit wiki,
  [How to generate voice files by batch](https://ck.uesp.net/wiki/How_to_generate_voice_files_by_batch).
  It says the official tools write a `.lip` with the Creation Kit, a `.xwm` with
  `xWMAEncode`, and then join them into a `.fuz`. It also gives the folder part of the path.
- The vanilla files, read with `openskycli audio info` and `openskycli audio voice-sweep`.
  The naming rule below was found from them. No published description matches the files.

All integers are little-endian.

## File layout

| Offset | Type | Field | Notes |
| --- | --- | --- | --- |
| 0x00 | char4 | Magic | `FUZE` |
| 0x04 | uint32 | Version | `1` in all vanilla files |
| 0x08 | uint32 | LIP Size | Bytes of lip data. May be 0 |
| 0x0C | bytes | LIP Data | The `.lip` file, unchanged |
| 0x0C + size | bytes | XWM Data | A complete RIFF/XWMA file, to the end |

The audio has no length field. It is everything after the lip data, and it is a whole
`.xwm` file. An example from a vanilla line: the header, 1,728 bytes of lip data, then
`RIFF`:

```text
00000000  46 55 5a 45 01 00 00 00  c0 06 00 00 01 00 00 00   FUZE............
000006cc  52 49 46 46 f4 28 00 00  58 57 4d 41 66 6d 74 20   RIFF.(..XWMAfmt
```

`LIP Size` 0 is valid and common. An `INFO` with the "no LIP file" flag has no lip data.

A wrong magic, a cut header, or a `LIP Size` that reaches past the end or eats the audio is
an error. A version other than `1` is not supported. OpenSky widens `LIP Size` to `Int`
before it adds offsets, so a huge value cannot overflow.

## Where a voice file lives

```text
sound\voice\<plugin file name>\<voice type editor ID>\<name>.fuz
```

The plugin is the one that defines the `INFO`: `skyrim.esm`, `dawnguard.esm`,
`hearthfires.esm`, or `dragonborn.esm` in vanilla. The voice type is the editor ID of the
speaker's `VTYP`. So one line can have many recordings, one per voice type. All vanilla
voice files are in `Skyrim - Voices_en0.bsa`.

## The file name rule

```text
<quest editor ID>_<topic editor ID>_<8 hex FormID>_<response number>.fuz
```

- quest: the editor ID of the `QUST` named in `QNAM` of the `INFO`'s `DIAL`.
- topic: the editor ID of that `DIAL`. It is often empty. About 35,000 vanilla files have
  no topic, so their names have a double underscore.
- FormID: the `INFO` FormID as the exporting plugin numbered it. The Creation Kit does not
  know the final load order. So the plugin's own records use index `00`, and a master's
  records use its position in the master list. That is why Dawnguard lines are
  `00xxxxxx`, and the few that override an `Update.esm` record are `01xxxxxx`.
- response number: the response number from `TRDT`, starting at 1. A line in several parts
  has `_1`, `_2`, and so on.

The two editor IDs share 25 characters:

1. The topic keeps at most 15 characters.
2. The quest is written in full if it fits in what is left of the 25. Otherwise it is cut
   to 10.
3. The topic then gets what the quest left, up to its own length.

Examples: `CWMission04` (11) stays whole next to `CWPrisonerWait` (14), because together
they are exactly 25. `BardSongs` (9) leaves 16 characters for the topic, one more than the
topic's own limit of 15. `BYOHHouseDialogueHousecarl` (26) becomes `byohhoused`, even with
no topic. Names are lowercase, like every VFS key.

Community descriptions of this rule disagree with each other and with the files. So the
archive was the authority: `openskycli audio voice-sweep` builds a name for every `INFO`
response and compares it with the archive listing. The rule above is what matches.

## Vanilla files

| Measure | Value |
| --- | --- |
| `.fuz` files | 75,408, all in `Skyrim - Voices_en0.bsa` |
| By plugin folder | skyrim 61,811, dragonborn 7,111, dawnguard 5,398, hearthfires 1,088 |
| Version | `1` in all |
| Audio | 44.1 kHz WMA version 2 (`0x0161`) in all |
| Channels | mono 74,869, stereo 539 |
| Lip data | 74,070 have it, 1,338 do not |
| Different file names | 44,325 |
| Names the rule builds | 43,753 (98.7%) |
| Names spelled differently | 86 |
| Names with no `INFO` response | 486 |

The two kinds of misses come from the game data, not from the rule:

- Spelled differently: the line was exported, then the quest or topic was renamed, and the
  file kept its old name. For example, some Companions lines are still named
  `c03_c03eorlund...` for records whose editor IDs now start with `C00`. Two names are
  broken: one has a space, and one is two names joined.
- No `INFO` response: the record was cut or renumbered after the audio was exported.

No correct rule can reach these files, and searching 75,408 names at runtime is not worth
it. A line that does not resolve is reported as a miss.

---
type: File Format
title: FUZE voice container (.fuz)
description: On-disk layout of Skyrim SE .fuz voice files - the FUZE header, the
  optional .lip blob, the embedded xWMA stream, and the voice-file naming rule derived
  from the vanilla archive listing.
tags: [format, audio, voice, dialogue, xwma]
timestamp: 2026-08-10T00:00:00Z
---

# FUZE voice container (.fuz)

Every recorded line of Skyrim SE dialogue ships as a `.fuz` file: a trivial
container that staples one `.lip` lip-sync blob to one `.xwm` audio stream so
the engine opens a single file per line. Item 17.5 frames that container. It
deliberately does **not** decode either half: the audio payload is handed to
the [xWMA container parser](/formats/xwm.md) and through it to the
[vendored ffmpeg WMA decoder](/decisions/ffmpeg-audio.md), and the lip blob is
handed on untouched for the lip-sync work in item 17.7.

## Contents

- References used
- File layout
- Validation and error policy
- Where a voice file lives
- The file-name rule
- How the rule was derived
- Vanilla sweep evidence
- Out of scope

## References used

Open sources only — no Bethesda code was read or transcribed:

- [xEdit `dev-4.1.6` `Core/wbDataFormatMisc.pas`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDataFormatMisc.pas)
  — read as documentation. Its `dfFUZ` definition is the layout: a four-character
  `FUZE` magic, a `uint32` `Version` whose declared default is `1`, a `uint32`
  `LIP Size`, `LIP Size` bytes of `LIP Data`, and the rest of the file as
  `XWM Data`.
- [CreationKit wiki, "How to generate voice files by batch"](https://ck.uesp.net/wiki/How_to_generate_voice_files_by_batch)
  — states what the container is for: the shipped pipeline runs the Creation Kit
  to write a `.lip`, `xWMAEncode` to write a `.xwm`, and a third tool to stitch
  the two into a `.fuz`. It also gives the directory half of the voice path.
- The install's own bytes, read at runtime through `openskycli audio info` and
  the `audio voice-sweep` walk. Everything below was confirmed against them; the
  naming rule was *derived* from them, because no published description of it
  matches the shipped files (see "How the rule was derived").

Impl: `opensky/Engine/Formats/FUZ/FUZFile.swift` (container) and
`opensky/Engine/Dialogue/VoiceFilePath.swift` plus `VoiceLineLocator.swift`
(naming). All integers are little-endian.

## File layout

| offset      | type   | field    | notes                                       |
| ----------- | ------ | -------- | ------------------------------------------- |
| 0x00        | char4  | Magic    | `FUZE`                                      |
| 0x04        | uint32 | Version  | `1` throughout the vanilla corpus           |
| 0x08        | uint32 | LIP Size | bytes of lip data that follow; may be zero  |
| 0x0C        | bytes  | LIP Data | `.lip` file contents, verbatim              |
| 0x0C + size | bytes  | XWM Data | a complete RIFF/XWMA file, to end of buffer |

There is no length field for the audio payload and no trailer: the payload is
whatever remains, and it is a whole `.xwm` file rather than a stripped stream,
so `XWMFile(data:)` reads it with no adapter beyond the offset. A vanilla line
looks like this at the boundary — header, 1,728 bytes of lip data, then `RIFF`:

```text
00000000  46 55 5a 45 01 00 00 00  c0 06 00 00 01 00 00 00   FUZE............
000006cc  52 49 46 46 f4 28 00 00  58 57 4d 41 66 6d 74 20   RIFF.(..XWMAfmt
```

`LIP Size` of zero is legal and common: an INFO carrying the `noLipFile` flag
ships a line with no lip blob at all, and `FUZFile.lipData` is `nil` for it.

## Validation and error policy

`FUZError.malformed` means the input violates the layout above;
`FUZError.unsupported` means a structurally valid container in a variant
OpenSky declines — currently any `Version` other than `1`. Both are typed and
`Equatable`; nothing traps, force-unwraps or reads out of bounds, which the
synthetic fixture tests in `openskyTests/FUZFileTests.swift` pin down: wrong
magic, every truncation of the twelve-byte header, a `LIP Size` past the end of
the file, a `LIP Size` that swallows the audio payload, an unknown version, and
an empty buffer. `LIP Size` is widened to `Int` before any offset arithmetic, so
a four-billion-byte claim is rejected rather than overflowed.

A `.fuz` whose payload is not xWMA fails on the audio side instead, with
`XWMError`, because framing the payload is a separate call (`FUZFile.audio()`).
That split is what lets the sweep report container failures apart from audio
failures.

## Where a voice file lives

```text
sound\voice\<plugin file name>\<voice type editor ID>\<name>.fuz
```

The plugin is the one that *defines* the INFO — `skyrim.esm`, `dawnguard.esm`,
`hearthfires.esm`, `dragonborn.esm` in vanilla — and the voice type is the
`VTYP` record's editor ID, which is how the speaker's voice selects between
tens of recordings of the same line. Every vanilla voice file is in one archive,
`Skyrim - Voices_en0.bsa`.

## The file-name rule

```text
<quest editor ID>_<topic editor ID>_<8 hex FormID>_<response number>.fuz
```

- **quest** is the editor ID of the QUST the INFO's owning DIAL names in `QNAM`.
- **topic** is the editor ID of that DIAL. It is frequently absent — roughly
  35,000 vanilla files spell it as nothing at all, which is why so many names
  carry a doubled underscore.
- **FormID** is the INFO's FormID as the *exporting* plugin numbered it: the
  Creation Kit does not know where the plugin it is editing will sit in a load
  order, so the plugin's own index is written as `00` while a master's index is
  its position in the master list. That is why every Dawnguard line is
  `00xxxxxx` and the handful overriding an Update.esm record are `01xxxxxx`.
- **response number** is `TRDT`'s one-based response number — the `_1`, `_2` of
  a line said in several parts.

The two editor IDs share one 25-character budget, and the sharing is the part
no community description gets right:

1. The topic reserves at most 15 characters.
2. The quest is spelled out in full if it fits what is left of the 25; otherwise
   it drops to 10 flat.
3. The topic then takes whatever the quest left, up to its own length.

So `CWMission04` (11) survives whole beside `CWPrisonerWait` (14) because they
total exactly 25, `BardSongs` (9) leaves 16 characters for a topic whose own
limit would have been 15, and `BYOHHouseDialogueHousecarl` (26) drops to
`byohhoused` even with no topic beside it at all. Names are lowercased, like
every VFS key.

## How the rule was derived

The community descriptions of this scheme conflict with each other and with the
shipped files, so the archive was treated as the authority.
`openskycli audio voice-sweep` rebuilds a name for every INFO response in every
loaded plugin, compares the result against the archive's own listing, and prints
each mismatch beside the editor IDs that produced it. The rule above is what
survives that comparison; each shape of the budget is pinned as a table row in
`openskyTests/VoiceFilePathTests.swift`, and
`VoiceRealDataTests.derivesVoiceFileNamesFromRecords()` re-runs the whole
comparison against the install.

## Vanilla sweep evidence

Vanilla Skyrim SE, 2026-08-10, `openskycli audio voice-sweep`:

| measure                       | value                                     |
| ----------------------------- | ----------------------------------------- |
| `.fuz` archive entries        | 75,408, all in `Skyrim - Voices_en0.bsa`  |
| by plugin directory           | skyrim 61,811, dragonborn 7,111, dawnguard 5,398, hearthfires 1,088 |
| container version             | `1` for every file                        |
| audio payload                 | 44.1 kHz WMAv2 (`0x0161`) throughout      |
| channels                      | mono 74,869, stereo 539                   |
| lip blob                      | 74,070 carry one, 1,338 do not            |
| framing failures              | 0                                         |
| declared playing time         | 4,728.3 minutes (1.43 GB of payload)      |
| distinct archive names        | 44,325 (the same line is recorded by many voice types) |
| names the rule reproduces     | 43,753 (98.71%)                           |
| names spelled differently     | 86 (0.19%)                                |
| names with no INFO response   | 486 (1.10%)                               |

The two residues are both Bethesda's, not the rule's:

- *Spelled differently* — the recording was exported, then the quest or topic
  was renamed in the plugin and the file name stayed frozen. The clearest
  cluster is a set of Companions lines still named `c03_c03eorlund...` for
  records whose editor IDs now read `C00`. Two more are literally corrupt: a
  file name containing a space and two names concatenated.
- *Names no INFO response* — the file outlived its record. The INFO was cut or
  renumbered after the audio was exported, so no naming rule can reach it; the
  sweep counts these separately for exactly that reason.

Neither residue is reachable by a correct rule, and neither is worth a fallback
scan of 75,408 entries at runtime: a line that does not resolve is reported as a
miss rather than played as silence.

No file names or bytes leave the install; the sweep prints counts, derived names
and per-file summary lines only, and its report goes to gitignored `logs/`.

## Out of scope

Decoding the `.lip` blob is item 17.7, which consumes `FUZFile.lipData` from
here; the TRI morph targets it drives are item 17.6. Playback, the voice submix
route and the playback clock are [World audio playback](/engine/audio.md).

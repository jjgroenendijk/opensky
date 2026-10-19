---
type: File Format
title: FormID and TES4 plugin header
description: TES4 header layout, master lists, and how a raw FormID resolves to a plugin
  and object ID.
tags: [format, plugin, esm, formid, records]
---

# FormID and TES4 plugin header

Every record has a 32-bit FormID at offset `0x0C` of its header (see
[ESM container](/formats/esm.md)). A raw FormID is relative to its file. Its top byte only
has a meaning together with the master list in that plugin's `TES4` header.

References: UESP [Mod File Format](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format)
(`TES4` record) and UESP [FormIDs](https://en.uesp.net/wiki/Skyrim_Mod:FormIDs).

## TES4 record

`TES4` is the first record of every plugin.

| Field | Type | Meaning |
| --- | --- | --- |
| `HEDR` | 12 bytes, required | float32 version, int32 record count, uint32 next object ID |
| `CNAM` | zstring | Author |
| `SNAM` | zstring | Description |
| `MAST` | zstring | Master file name. One per master, in order |
| `DATA` | uint64 | Follows each `MAST`. Always 0 |

OpenSky skips `ONAM`, `INTV`, `INCC`, and fields added by mod tools. Text follows the
[string decoding](/decisions/string-decoding.md) policy.

The `HEDR` version is 1.71 in Skyrim SE. The record count includes groups and is not
reliable. For example, `Skyrim.esm` says 920,181, while a walk finds 869,687 records and
50,494 groups. OpenSky never uses it.

The flags of the `TES4` record are plugin flags: `0x1` master (ESM), `0x80` localized
(text is in [string tables](/formats/strings.md)), `0x200` light (ESL).

## FormID layout

`0xIIOOOOOO`: the top byte `II` is a master index, and the low 24 bits are the object ID.

The master index points into the `MAST` list of the file that holds the FormID:

- index < number of masters: the record belongs to that master.
- index == number of masters: the record belongs to this plugin.
- index > number of masters: malformed. OpenSky treats it as this plugin, like xEdit.
- `0x00000000` is a null reference.

In vanilla, the highest index used is exactly the number of masters. For example, 1 in
`Update.esm` and 2 in `Dawnguard.esm`. Vanilla masters: `Update.esm` has `Skyrim.esm`.
`Dawnguard.esm`, `HearthFires.esm`, and `Dragonborn.esm` have `Skyrim.esm` and `Update.esm`.

## Load-order space

The index the game console shows is different. It depends on the user's full load order.
The record stores name a record by (plugin file name, object ID), which does not depend on
load order. The game session works in the load-order space instead, as the console does:
`Skyrim.esm` FormIDs keep their value and a DLC record gets its load position as top byte.
The cell builder, the quest and dialogue stores, and every store built over the whole load
order number their records this way. A store keyed by (plugin, object ID) resolves such a
FormID through the reserved plugin name `<load order>`.

A later plugin's record is decoded inside a decode scope. In the scope, every FormID the
decoder reads moves into the load-order space, and every string-table ID keeps the name of
its plugin. So each field of each record type is translated, such as a reference's base, its
linked references, and its script properties, and no decoder needs its own renumbering.
Outside a scope, a FormID stays as written.

Every engine and CLI path reads plugins as one load order, as the game does. The one entry
point is `ActiveLoadOrder.open(root:)`: it reads `plugins.txt` (or the vanilla fallback), opens
each active plugin, and builds the FormID space. A tool that opened `Skyrim.esm` alone would
miss every DLC and mod override, such as the Hearthfire edits to Whiterun's cells.
`make load-order-only` fails on a single-file `ESMFile(url:)` outside the format modules.
Assets follow the same rule through the virtual file system, where loose files win over
archives.

A plugin that lists its masters in load order and loads right after them keeps every FormID
unchanged, so no renumbering is needed. Every official plugin does: `Update.esm` lists
`Skyrim.esm`, the DLCs list both, and the Creation Club plugins checked
list all five official masters.

Conditions stay as their plugin wrote them. The evaluator translates each FormID word into
the load-order space when it runs. For example, `Dragonborn.esm` writes its own quests as
`02xxxxxx`. It loads fifth, so in the load-order space they are `04xxxxxx`. Read raw, `02` is
`Dawnguard.esm`, and the condition would name a quest that does not exist.
For identities that must stay stable during a session, see [runtime reference identity](/engine/runtime-state.md).

## Light plugins

A light plugin (ESL) has the `0x200` flag on its `TES4` record, or the `.esl` extension. The
game treats an `.esl` file as light even without the flag. Inside the file, a light plugin
encodes master indices as above, and its own objects use only the low 12 bits.

At runtime, all light plugins share the top byte `0xFE`: `FE xxx yyy`. The 12 bits `xxx` are
the plugin's slot, counted in load order over light plugins only. The 12 bits `yyy` are the
object ID. Full plugins count their own positions from `00` and skip the light ones.
For example, with `Skyrim.esm`, `Small.esl`, and `Mod.esp` active, `Mod.esp` is `01` and
`Small.esl` object `0x801` is `FE000801`. Sources: UESP
[FormIDs](https://en.uesp.net/wiki/Skyrim_Mod:FormIDs), and the `.ess` file's own light
plugin list (see [ESS](/formats/ess.md)).

The Creation Kit wiki gives no layout for light plugins. Its
[Data file](https://ck.uesp.net/wiki/Data_file) page says light masters came with SE 1.5.3
and points to the Fallout 4 wiki. Its
[GetFormFromFile](https://ck.uesp.net/wiki/GetFormFromFile_-_Game) page says the top byte
of the given ID is unused, so `0000ABCD` and `0400ABCD` name the same form.

The load-order space follows this rule, as does `Game.GetFormFromFile`: it drops the top
byte, and for a light file it keeps only the low 12 bits. A light plugin FormID whose object
ID needs more than 12 bits cannot be named in the space and becomes the null FormID. A load
order with no light plugins keeps every plugin on its plain position. On the install checked,
`_ResourcePack.esl`, `ccBGSSSE037-Curios.esl`, and `ccQDRSSE001-SurvivalMode.esl` carry the
flag. `ccBGSSSE001-Fish.esm` does not.

## Record index across plugins

To find the winning version of a record, OpenSky walks the active plugins from lowest to
highest priority. It resolves each FormID through that plugin's master list. Master names
match plugin file names without case. A later valid record replaces an earlier one.

A deleted record, a broken field, or an unreadable group or plugin never removes the last
valid version. When the winning override cannot be decoded, OpenSky falls back to the last
version that can.

Real data check: `Skyrim.esm:013794` resolves to `ActorTypeNPC`.

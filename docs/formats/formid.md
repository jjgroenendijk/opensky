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

A plugin that lists its masters in load order and loads right after them keeps every FormID
unchanged, so no renumbering is needed. Every official plugin does: `Update.esm` lists
`Skyrim.esm`, the DLCs list both, and the Creation Club plugins checked
list all five official masters.

Conditions stay as their plugin wrote them. The evaluator translates each FormID word into
the load-order space when it runs. For example, `Dragonborn.esm` writes its own quests as
`02xxxxxx`. It loads fifth, so in the load-order space they are `04xxxxxx`. Read raw, `02` is
`Dawnguard.esm`, and the condition would name a quest that does not exist.
For identities that must stay stable during a session, see [runtime reference identity](/engine/runtime-state.md).

Light plugins (ESL) use the `0xFE` prefix only at runtime. Inside the file, they encode
master indices as above. OpenSky does not model the `0xFE` slots yet, so the Load Order
panel shows a plain position, not a runtime index.

## Record index across plugins

To find the winning version of a record, OpenSky walks the active plugins from lowest to
highest priority. It resolves each FormID through that plugin's master list. Master names
match plugin file names without case. A later valid record replaces an earlier one.

A deleted record, a broken field, or an unreadable group or plugin never removes the last
valid version. When the winning override cannot be decoded, OpenSky falls back to the last
version that can.

Real data check: `Skyrim.esm:013794` resolves to `ActorTypeNPC`.

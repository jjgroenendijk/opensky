---
type: File Format
title: FormID and TES4 plugin header
description: TES4 header layout, master lists, and how a raw FormID resolves to a plugin and an
  object ID.
tags: [format, plugin, esm, formid, records]
---

# FormID and TES4 plugin header

Every record has a 32-bit FormID at offset `0x0C` of its header (see
[ESM container](/formats/esm.md)). A raw FormID only has meaning inside its own file. Its top
byte points into that plugin's master list, which is in the `TES4` header.

Sources: UESP [Mod File Format](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format) (the
`TES4` record), and UESP [FormIDs](https://en.uesp.net/wiki/Skyrim_Mod:FormIDs).

## TES4 record

The first record of every plugin.

| Field | Type | Meaning |
| --- | --- | --- |
| `HEDR` | 12 bytes, required | File stats, below |
| `CNAM` | zstring | Author, optional |
| `SNAM` | zstring | Description, optional |
| `MAST` | zstring | Master file name. One per master, in order |
| `DATA` | uint64 | After each `MAST`. Always 0 |

`HEDR` is a float32 version (1.71 for SSE), an int32 record count, and a uint32 next object
ID. OpenSky skips `ONAM`, `INTV`, and `INCC`.

The record flags of `TES4` describe the plugin: `0x1` ESM, `0x80` localized (text lives in
[string tables](/formats/strings.md)), `0x200` ESL.

Do not trust the `HEDR` record count. It counts groups too. `Skyrim.esm` says 920181. A walk
finds 869687 records and 50494 groups, which add up to it.

## FormID layout

`0xIIOOOOOO`: the top byte `II` is a master index. The low 24 bits are the object ID.

The index points into this plugin's own `MAST` list:

- Index less than the master count: the record belongs to that master.
- Index equal to the master count: the record belongs to this plugin.
- Index greater than the master count: malformed. OpenSky treats it as this plugin, as xEdit
  does.
- `0x00000000` means "no reference".

Example: `Update.esm` has one master, `Skyrim.esm`. Inside `Update.esm`, a FormID that
starts with `0x00` names a `Skyrim.esm` record. A FormID that starts with `0x01` names an
`Update.esm` record.

In vanilla files, the largest master index used equals the master count exactly. There are
no out-of-range indices.

The index the game console shows is different. It depends on the user's full load order.
OpenSky names a record by plugin file name plus object ID, which does not depend on load
order. For identity that must last a whole session, see
[runtime reference identity](/engine/runtime-state.md).

## ESL plugins

The `0xFE` prefix exists only at runtime. A FormID inside a plugin file never uses it. An
ESL-flagged plugin encodes master indices in the normal way. OpenSky does not assign `0xFE`
slots yet, so the Load Order panel shows a plain position.

## Records across plugins

To find the winning version of a record, OpenSky visits the active plugins from low to high
priority. It resolves each FormID through the plugin's master list. A later valid record
replaces an earlier one. A deleted record, a malformed field, or an unreadable plugin never
removes the last valid version.

When the winning override cannot be decoded, OpenSky falls back to the last version that
can. A caller can tell apart "no such record", "a record that does not decode", "a null
reference", and "an unknown plugin".

Plugin names in `MAST` are matched to files case-insensitively.

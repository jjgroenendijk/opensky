---
type: File Format
title: Enchantments (ENCH)
description: ENCH and ENIT layout, the base chain, and how weapons and armor link to an
  enchantment.
tags: [format, esm, magic, record, enchantment]
---

# Enchantments

An ENCH is the effect list on an enchanted weapon, armor piece, or staff. A weapon or armor
names it through `EITM` ([item records](/formats/item-records.md)). The effect records and
the cost formula are on [magic records](/formats/magic-records.md).

Sources: UESP [`/ENCH`](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/ENCH) and xEdit
dev-4.1.6 `Core/wbDefinitionsTES5.pas`. All integers and floats are little-endian.

## Fields

xEdit defines ENCH as `wbEDID, wbObjectBounds, wbFULL, wbStruct(ENIT, ...), wbEffectsReq`.
An ENCH carries none of the other carried-item fields.

| field | type | meaning |
|---|---|---|
| `EDID` | zstring | editor ID |
| `OBND` | 12 bytes | object bounds; always zero on vanilla |
| `FULL` | lstring | name shown on the enchanted item |
| `ENIT` | 32 or 36 bytes | see below |
| `EFID`/`EFIT`/`CTDA` | repeated run | effect list |

| offset | type | meaning |
|---|---|---|
| `0x00` | int32 | cost; used only when the manual-cost flag is set |
| `0x04` | uint32 | flags |
| `0x08` | uint32 | cast type (same values as MGEF) |
| `0x0C` | int32 | enchantment amount, the full charge of the item |
| `0x10` | uint32 | delivery (same values as MGEF) |
| `0x14` | uint32 | enchantment type |
| `0x18` | float32 | charge time |
| `0x1C` | FormID | base `ENCH` this one comes from |
| `0x20` | FormID | worn restrictions, an `FLST` of slots; optional |

UESP records a 32-byte variant (form version 37) without the last link. xEdit marks it
`SetOptionalFrom(8)`. The vanilla install has 4 of these short records.

Flag bits: 0 manual cost (xEdit "No Auto-Calc", UESP "ManualCalc") and 2 extend duration on
recast. Enchantment types: `0x06` enchantment and `0x0C` staff enchantment.

The base link forms a chain. On vanilla the longest chain has three entries. A mod can make
the chain loop, so OpenSky stops at a repeated entry and at a fixed cap.

A weapon names its enchantment with `EITM` and its charge with `EAMT`. Armor has `EITM` only.
xEdit builds both from `wbEnchantment` and adds `EAMT` only on WEAP.

## Vanilla counts

Measured on this machine's active load order: 766 ENCH records, 757 unique. 762 `ENIT` are
36 bytes and 4 are 32 bytes. 59 set the manual-cost flag, 364 name a base enchantment, and
80 name a worn-restrictions list. Every `EITM` on the 3,025 enchanted weapons and 2,885
enchanted armor pieces resolves.

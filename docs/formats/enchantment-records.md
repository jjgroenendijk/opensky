---
type: File Format
title: Enchantment records
description: ENCH and ENIT layouts, how weapons and armor name an enchantment, and base
  enchantment chains.
tags: [format, esm, magic, enchantment, record]
---

# Enchantment records (ENCH)

`ENCH` is an enchantment. A weapon or armor names it through `EITM`. Its effect list and cost
formula are the same as a spell's (see [magic records](/formats/magic-records.md)). Sources:
UESP [ENCH](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/ENCH); xEdit `dev-4.1.6`
`Core/wbDefinitionsTES5.pas`.

## Fields

An enchantment is identity, the `ENIT` header, and the effect list. xEdit spells the record as
`wbEDID, wbObjectBounds, wbFULL, wbStruct(ENIT, ...), wbEffectsReq`. An `ENCH` has none of the
other carried-item fields.

| Field | Type | Meaning |
| --- | --- | --- |
| `EDID` | zstring | Editor ID |
| `OBND` | 12 bytes | Bounds. Always 0 in vanilla |
| `FULL` | lstring | Name shown on the enchanted item |
| `ENIT` | 32 or 36 bytes | Below |
| `EFID`, `EFIT`, `CTDA` | effect list | Effects |

A weapon names its enchantment with `EITM` and its charge with `EAMT`. Armor uses `EITM` only.
xEdit builds both from `wbEnchantment`, and asks for the `EAMT` version only on `WEAP`. In
vanilla, every `EITM` on weapons and armor resolves.

## ENIT

| Offset | Type | Meaning |
| --- | --- | --- |
| `0x00` | int32 | Cost. Used only with the manual cost flag |
| `0x04` | uint32 | Flags |
| `0x08` | uint32 | Cast type |
| `0x0C` | int32 | Enchantment amount: the charge of a full item |
| `0x10` | uint32 | Delivery |
| `0x14` | uint32 | Enchantment type |
| `0x18` | float32 | Charge time |
| `0x1C` | FormID | Base `ENCH` this one comes from |
| `0x20` | FormID | Worn restrictions: an `FLST` of allowed slots |

The last field is optional. UESP describes a 32-byte variant (form version 37) without it, and
xEdit marks it `SetOptionalFrom(8)`. Vanilla has a few 32-byte `ENIT` fields, so this case is
real.

Flag bits: 0 manual cost (xEdit "No Auto-Calc", UESP "ManualCalc"), 2 extend duration on
recast. Enchantment types: `0x06` enchantment, `0x0C` staff enchantment. The two values are far
apart, so OpenSky does not fold other values into either.

UESP gives the same cost curve for `ENCH` as for `SPEL`, so both use the same formula.

## Base chains

An enchantment can name a base enchantment, which can name another. OpenSky walks the chain,
nearest first. It stops on a loop and at a fixed length. Vanilla chains have at most three
entries. The Asset Browser shows the chain under a selected `ENCH`.

## Bad input

A wrong record type is an error. A broken field is counted, and the other fields still decode.
Unknown enum values are kept raw.

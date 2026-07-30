---
type: File Format
title: Papyrus attachment data (VMAD)
description: Skyrim ESM script attachments, typed property values, object
  references, fragment skip policy, and PEX backing-variable binding.
tags: [format, plugin, papyrus, vmad, formid]
timestamp: 2026-07-30T00:00:00Z
---

# Papyrus attachment data (VMAD)

`VMAD` fields attach compiled Papyrus scripts to ESM records and supply the
property values authored for each attachment. OpenSky decodes the shared
primary-script section, resolves direct object values to
[`ReferenceKey`](/formats/formid.md), and binds compatible values to the actual
automatic backing-variable names stored in the
[PEX property metadata](/formats/pex.md).

Layout sources:

* [xEdit dev-4.1.6 `wbDefinitionsTES5.pas`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsTES5.pas),
  especially `wbScriptPropertyObject`, `wbScriptEntry`, `wbVMAD`, and the five
  fragmented variants; and
* [UESP, VMAD Field](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/VMAD_Field),
  cross-checked for version-dependent status bytes and array availability.

No game field bytes or compiled scripts are tracked. Synthetic fixtures build
every encoded case in memory, and the real-data evidence below records only
aggregate counts in the repository.

## Contents

* [Header and scripts](#header-and-scripts)
* [Properties](#properties)
* [Object references](#object-references)
* [Fragments and aliases](#fragments-and-aliases)
* [Record integration](#record-integration)
* [PEX binding](#pex-binding)
* [Defensive decode policy](#defensive-decode-policy)
* [Vanilla sweep evidence](#vanilla-sweep-evidence)
* [Scope](#scope)

## Header and scripts

The field starts with three little-endian values:

| type | field | OpenSky policy |
| --- | --- | --- |
| `int16` | version | versions 2 through 5 |
| `int16` | object format | 1 or 2; selects object word order |
| `uint16` | script count | bounded by the remaining field bytes |

Each script then contains:

| type | field |
| --- | --- |
| `uint16` + bytes | script name |
| `uint8` | flags when version is at least 4 |
| `uint16` | property count |
| repeated | property entries |

Script flag bit 0 means inherited and bit 1 means removed. A removed attachment
remains represented for diagnostics but is never instantiated.

The length-prefixed strings use the VMAD text encoding. OpenSky decodes them as
Windows-1252, matching the plugin text policy; an invalid sequence is a typed
string error. The observed vanilla script and property names are ASCII.

## Properties

A property is its length-prefixed name, one-byte type, one-byte flags when the
VMAD version is at least 4, and a type-selected value. Property flag bit 0 means
edited and bit 1 means removed. Removed properties are decoded to keep the
reader aligned, tallied, and excluded from binding.

| type byte | value | payload |
| ---: | --- | --- |
| 0 | none | no payload |
| 1 | object | eight-byte object union |
| 2 | string | `uint16` length plus bytes |
| 3 | integer | signed `int32` |
| 4 | float | IEEE-754 binary32 |
| 5 | boolean | one byte; zero is false |
| 11 | object array | `uint32` count plus object values |
| 12 | string array | `uint32` count plus strings |
| 13 | integer array | `uint32` count plus `int32` values |
| 14 | float array | `uint32` count plus binary32 values |
| 15 | boolean array | `uint32` count plus bytes |

Arrays are valid from version 5. Every count is checked against a conservative
minimum element width before allocation, so a large count in a short field
throws rather than requesting attacker-controlled memory.

## Object references

Both object encodings occupy eight bytes. Only their word order changes:

| object format | first 4 bytes | next 2 bytes | last 2/4 bytes |
| ---: | --- | --- | --- |
| 1 | FormID | signed alias | unused `uint16` |
| 2 | unused `uint16` | signed alias | FormID |

Alias `-1` means the FormID is a direct object. Any other alias selects an
alias on the quest named by the FormID. Direct, non-null values pass through
the owning plugin's `FormIDResolver` and become a normalized `ReferenceKey`.
The raw FormID never becomes a session identity by itself.

The zero FormID is Papyrus `None`. An alias object, an unresolved FormID, or a
resolved key for which the world has not supplied an opaque handle does not
invent an object. Binding leaves the compiler default intact, logs the skip,
and increments the matching reason tally.

## Fragments and aliases

`INFO`, `PACK`, `PERK`, `QUST`, and `SCEN` append record-specific fragment
structures after the common script list. M11.1 does not execute those
fragments. Once the primary list is decoded, `ScriptData` recognizes those
five carriers, records one reason-tagged fragment-section skip, and consumes
the bounded field remainder. A remainder on any other record type is a typed
error rather than guessed framing.

Quest alias script sections are likewise not modeled. Object values that name
an alias are retained as `ScriptObjectReference`, counted as alias skips, and
never collapsed into a direct world reference. Both decisions keep later
fragment and quest-alias work additive.

## Record integration

`ScriptData` is a field-loop accumulator: `decode(field:)` returns false for a
non-`VMAD` field, allowing record decoders to forward fields without a second
switch. It currently hangs from:

* `PlacedReference` for `REFR`;
* `PlacedActor` for `ACHR`;
* `ActorBase` for `NPC_`; and
* `ModelBase` for `MSTT`, `TREE`, `FURN`, `ACTI`, `CONT`, and `DOOR`.

The independent real-data sweep decodes `VMAD` directly on every record type,
including carriers whose larger record model does not exist yet. That keeps
format coverage broader than the current world consumers.

## PEX binding

`AttachedScript.binding` locates a property case-insensitively through the
child-to-parent PEX script chain. An attachment binds only when the PEX
property is automatic and names a decoded backing variable. The dictionary
passed to `PapyrusRuntime.makeInstance` uses that exact
`automaticVariableName`; it never constructs a name from the source property.

Scalar and array values convert to the corresponding `PapyrusValue`, then pass
the runtime's declared-type check. Direct objects take the complete path:

`FormIDResolver` -> `ReferenceKey` -> caller-owned `PapyrusObjectHandle`.

Removed, missing, manual, or type-mismatched properties and unresolved objects
stay at the PEX compiler default. `ScriptBinding` returns the applied
initial-value dictionary, successfully resolved keys, and ranked skip tally so
callers and probes can explain the result.

The vanilla probe observed 46,263 automatic property attachments. Every one
used the conventional `::Property_var` spelling, and each stored name selected
an actual PEX variable. This is evidence about that corpus, not an
implementation rule: the synthetic binding test deliberately uses unrelated
names such as `::opaque_backing_17` and proves the decoded PEX name wins.

## Defensive decode policy

The decoder throws `ScriptDataError` for:

* a truncated primitive or byte run;
* a VMAD version outside 2 through 5;
* an object format other than 1 or 2;
* an invalid length-prefixed string;
* a count impossible for the bounded remainder;
* an array before version 5;
* an unknown property type; or
* unexpected trailing bytes on a non-fragment carrier.

ESM `XXXX` extension handling belongs to `ESMField.parseAll`. `ScriptData`
therefore receives the already-expanded payload and has no 65,535-byte
assumption. A synthetic test routes a string property in a `VMAD` field larger
than 64 KiB through the normal `REFR` decoder.

## Vanilla sweep evidence

`ScriptDataRealDataTests` ran through `make realtest` on 2026-07-30 against the
retail `Skyrim.esm`. It decoded every field, asserted the exact census below,
sampled 32 direct values whose normalized keys name records present in the
plugin, and wrote those local key samples to gitignored
`logs/vmad-sweep.log`.

| measure | observed |
| --- | ---: |
| records walked | 869,687 |
| unreadable records | 0 |
| VMAD fields / decode failures | 16,133 / 0 |
| attached scripts / properties | 17,407 / 46,493 |
| version 4 / version 5 fields | 2,561 / 13,572 |
| object format 1 / format 2 fields | 2,705 / 13,428 |
| direct / null / dangling object values | 27,044 / 201 / 38 |
| alias object skips | 12,399 |
| removed property skips | 7 |
| fragmented field sections | 6,988 |

The only array type present was boolean array, in two properties; the synthetic
matrix remains the evidence for every other array representation. Fragment
skips were 5,257 `INFO`, 856 `QUST`, 557 `SCEN`, 313 `PACK`, and 5 `PERK`.

The PEX half loaded 4,071 distinct script objects while following inheritance.
It found 46,263 automatic attachment properties, 199 manual properties, 24
names absent from the available PEX chain, no missing script files, no missing
automatic backing names, and no backing name that failed to select a decoded
variable. An absent or incompatible property is intentionally a default-value
skip, not a malformed VMAD field.

## Scope

This layer decodes attachment data and creates one headless script instance. It
does not schedule events, own world-object handle lifetimes, execute fragment
tables, resolve quest aliases, or define native game functions. Those are
separate runtime responsibilities built on the typed attachment and binding
seams.

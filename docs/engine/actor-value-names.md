---
type: Subsystem
title: Actor value names
description: The one table that maps a condition's actor value index and a Papyrus actor value name
  to the same value, how names are matched, and the legacy names three AVIF records use.
tags: [engine, actors, conditions, papyrus]
---

# Actor value names

Two places name an [actor value](/engine/actor-values.md) by its vanilla identity, and they spell it
differently. A `CTDA` condition parameter holds a signed index. A Papyrus native holds a name
string. One table serves both.

## The table

The table is xEdit's `wbActorValueEnum`, from dev-4.1.6 `Core/wbDefinitionsTES5.pas`, copied as is:
0 `Aggression` to 163 `Reflect Damage`, with -1 spelled `None`. The `Unknown NN` placeholders xEdit
keeps for indices Skyrim leaves unnamed stay in. A table that renumbered around a gap would put every
later index one off. Health is 24, magicka 25, and stamina 26 because that file says so.

## Matching names

Names are matched with every character that is not a letter or digit removed, and the rest in lower
case. So xEdit's `One-Handed`, Papyrus's `OneHanded`, and a script's `"one handed"` are one name.

Papyrus uses a few different words for the same value. For example, `Marksman` is index 8, which
xEdit spells `Archery`. The name lookup does not add aliases for these. A failed lookup then means
only "no vanilla actor value has this name".

Three vanilla `AVIF` records use that older vocabulary in their editor IDs: `AVMarksman`,
`AVSpeechcraft`, and `AVMysticism`. Those three are mapped, through a separate lookup that only
[actor value information](/formats/actor-value-information.md) uses. The mapping was read from the
data: each record's own `FULL` string resolves through the `Skyrim.esm` string table to `Archery`,
`Speech`, and `Illusion`.

## Every index answers

Every entry in the table is stored ([actor value store](/engine/actor-value-store.md)). So the only
miss left is an index outside the table. A condition reports it as a false with a reason and a tally
bucket. A Papyrus native reports a failure and returns the call's declared default.

`Skyrim.esm` has 607 `GetActorValue` and `GetActorValuePercent` conditions. 68 name a primary and 539
name another actor value, and all of them resolve their parameter.

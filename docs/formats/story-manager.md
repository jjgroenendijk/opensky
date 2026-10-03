---
type: File Format
title: Story manager records
description: Skyrim SE SMBN, SMQN and SMEN story-manager nodes.
tags: [format, plugin, quest]
---

# Story manager records

The story manager starts quests when game events happen. Its nodes form a tree: event nodes
(`SMEN`) name an event, branch nodes (`SMBN`) group children, and quest nodes (`SMQN`) list
the quests to start. The runtime is on the [story manager](/engine/story-manager.md) page.

Source: xEdit `dev-4.1.6`, commit `9fb0168`,
[`wbDefinitionsTES5.pas`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsTES5.pas)
and
[`wbDefinitionsCommon.pas`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsCommon.pas).
All integers are little-endian. Field and size counts were checked on the five masters of the
install with a field census.

## Fields

All three types share one layout.

| Field | Type | Meaning |
| --- | --- | --- |
| `EDID` | zstring | Editor ID |
| `PNAM` | FormID | Parent node |
| `SNAM` | FormID | Previous sibling, null for the first child |
| `CITC`, `CTDA` | conditions | When the node may run |
| `DNAM` | uint32 | Flags: 0x01 random, 0x02 warn if no child quest started; quest nodes add 0x10000, 0x20000, 0x40000 |
| `XNAM` | uint32 | Maximum concurrent quests |
| `MNAM` | uint32 | Number of quests to run |
| `QNAM` | uint32 | Declared quest count |
| `NNAM` | FormID | A `QUST`, repeated |
| `FNAM` | uint32 | After an `NNAM`: the reset timer runs a full day |
| `RNAM` | float | After an `NNAM`: hours until reset |
| `ENAM` | 4 chars | Event type of an `SMEN`, such as `KILL` |

Sibling order comes from the `SNAM` chain, not from file order. A `QNAM` that differs from
the number of `NNAM` entries is tallied as a mismatch.

## The tree

OpenSky rebuilds the tree once, when the store is built:

1. Each node goes under its parent. A node whose parent is null, or names a record that is
   not in the store, is a root. The second kind is also counted as an orphan.
2. Siblings are ordered by following the previous-sibling links from the sibling whose
   link is null. A group with more than one such start, or with a loop, is counted as a
   broken chain and keeps file order for the nodes the chain does not reach.
3. A node that no root reaches sits on or below a parent cycle. It is counted as
   unreachable. No walk follows a link twice, so a cycle never hangs.

Event nodes are not roots. In the vanilla data every `SMEN` sits under one branch node named
`Root`, so event nodes are found by a walk from the roots in sibling order, and grouped by their
event code, such as `KILL`. Each `SMQN` quest entry is
indexed by quest, so a quest finds the nodes that can start it. The event of any node is
the event of the nearest event node on its path from the root.

On the five masters the 657 nodes form one tree, 6 levels deep. Every parent resolves.
10 child groups have a split sibling chain and keep file order.

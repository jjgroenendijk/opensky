---
type: File Format
title: Idle records
description: Skyrim SE IDLE animations, ANIO animated objects and IDLM idle markers.
tags: [format, plugin, animation]
---

# Idle records

`IDLE` records form a forest of animation choices. The game walks it from a root, testing
each node's conditions. `ANIO` is a prop held during an idle. `IDLM` is a placed marker
where an actor plays idles.

Source: xEdit `dev-4.1.6`, commit `9fb0168`,
[`wbDefinitionsTES5.pas`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsTES5.pas)
and
[`wbDefinitionsCommon.pas`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsCommon.pas).
All integers are little-endian. Field and size counts were checked on the five masters of the
install with a field census.

## IDLE

| Field | Type | Meaning |
| --- | --- | --- |
| `EDID` | zstring | Editor ID |
| `CTDA` | conditions | When the idle may play |
| `DNAM` | zstring | Behavior file name |
| `ENAM` | zstring | Animation event |
| `ANAM` | 2 FormIDs | Parent and previous sibling, each an `IDLE`, an `AACT`, or null |
| `DATA` | 6 bytes | Loop min, loop max, flags, animation group section (uint8 each), replay delay (uint16) |

The top idles of a tree usually name an `AACT` action as their parent, not null. The
action is what starts the walk. Parent links can form a cycle in modded data, so a walk
over them must stop at a node it has already seen.

## ANIO

| Field | Type | Meaning |
| --- | --- | --- |
| `MODL`, `MODT` | model group | The prop |
| `BNAM` | zstring | Unload event |

## IDLM

| Field | Type | Meaning |
| --- | --- | --- |
| `OBND` | 12 bytes | Bounds |
| `IDLF` | uint8 | Flags: 0x01 run in sequence, 0x04 do once, 0x10 ignored by sandbox |
| `IDLC` | uint8 | Declared idle count |
| `IDLT` | float | Idle timer |
| `IDLA` | FormID array | The `IDLE` records, 4 to 40 bytes on the install |
| `MODL` | model group | Marker mesh |

An `IDLC` that differs from the `IDLA` length is tallied.

## The tree

OpenSky rebuilds the tree once, when the store is built:

1. Each `AACT` action is a root node. Each idle goes under its parent. An idle whose
   parent is null, or names a record that is neither an idle nor an action, is a root.
   The second kind is also counted as an orphan.
2. Children of one parent are ordered by following the previous-sibling links from the sibling whose
   link is null. A group with more than one such start, or with a loop, is counted as a
   broken chain and keeps file order for the nodes the chain does not reach.
3. A node that no root reaches sits on or below a parent cycle. It is counted as
   unreachable. No walk follows a link twice, so a cycle never hangs.

The top idles are the root idles plus the children of each action. The store groups them
by action and by the `DATA` animation group section, and lists the idles
of an `IDLM` in `IDLA` order.

On the five masters the winning records give 4,154 idles. 1,488 are top idles, and 1,115 of
those hang under an action. No parent is dangling and no parent link loops. The deepest
tree has 8 levels, the action included. 66 child groups have a split sibling chain, most
of them under an action, so their file order is kept.

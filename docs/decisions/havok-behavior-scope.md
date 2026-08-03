---
type: Decision
title: Havok behavior graph scope for player locomotion
description: Reimplement the Havok Behavior graph in full over the class set the vanilla
  player files actually use, rather than approximating it with a native state machine;
  swim included, first person with full arms, and a clean-room sourcing rule.
tags: [decision, havok, hkx, behavior, animation, locomotion, milestone-14]
timestamp: 2026-08-03T00:00:00Z
---

# Havok behavior graph scope

Closes milestone item 14.1. Binding for 14.2 (node and modifier classes), 14.3 and 14.4
(evaluation), and 14.5 (the runtime bridge that drives the player), and for every later
milestone that animates a creature rather than the player.

## Context

The direction was set on 2026-07-20 and recorded only as a line in
[the change log](/log.md): reimplement Havok Behavior graphs, for vanilla movement feel
and for animation-mod compatibility, in preference to a native state machine of our own.
Nothing wrote down what "reimplement" bounded, and M14 has since been split into eight
items that all depend on the answer. This document is that answer, and it is written
after the measurement rather than before it.

What already existed when M14 opened: the packfile container from M6
([HKX container](/formats/hkx-container.md)), `hkaSkeleton`
([hkaSkeleton](/formats/hka-skeleton.md)), and spline-compressed clip sampling
([hkaSplineCompressedAnimation](/formats/hka-animation.md)). Those three give a rig and a
clip. Nothing chose *which* clip, or blended two of them, which is the whole of what a
behavior graph does.

## Decision

Implement full-graph evaluation over the class set the vanilla player behavior files
actually contain. Concretely:

**Every node class present in the vanilla player graph files gets a decoder**, and the
evaluator walks a class registry rather than a hand-written switch over the handful of
classes locomotion happens to need. The alternative — decode the graph's variables and
events but drive the actual selection from bespoke Swift — was rejected because it makes
every animation mod a special case, which is the outcome the 2026-07-20 decision was
taken to avoid.

**Swim is in the milestone**, not deferred to a water milestone. It is a locomotion state
inside the same graph as walk, run, and sprint; splitting it out would mean shipping a
player who moves correctly until they step into a river.

**First person is in scope with full arms**, not a camera mode with the third-person
graph behind it. The install ships a complete parallel behavior set under
`_1stperson\` — its own project file, its own character file, and 17 of its own behavior
files — and the census below confirms it is a peer of the third-person set rather than a
subset.

**Sourcing is clean-room and stays that way.** Class layouts come from independent
open-source reimplementations — ret2end/HKX2Library (MIT), soulsmods/DSMapStudio HKX2
(MIT), exyorha/hkxparse (MIT) — and from bytes observed in the user's own lawfully-owned
files. No Havok SDK headers, no decompiled or leaked source, no Creation Kit or SKSE
internals. Every layout that lands is probe-verified against the install before it is
documented, and the documentation cites which project the offsets came from. This is the
same rule the rest of the project runs under (AGENTS.md "Legal & IP boundary"); it is
restated here because behavior classes are the largest single body of Havok layout the
project will reimplement, and the temptation to shortcut it is proportional.

**Evaluation is the goal; physics is not.** Ragdoll and the physics classes that appear
beside behavior data are out of scope for M14 and belong to M15.

## Evidence: the census

All numbers below come from `HKBBehaviorCensusRealDataTests`, run against the user's own
install on 2026-08-03 over every `.hkx` under `meshes\actors\character\`. The full report
is captured to `logs/hkx-behavior-census.log`, which is gitignored and never committed —
it is derived from game content. Reproduce it with
`make realtest T='HKBBehaviorCensusRealDataTests/censusesCharacterBehaviorFiles()'`, or
inspect one file with `openskycli hkx <key>`. The layout tables the census rests on are
in [HKX behavior graph objects](/formats/hkx-behavior.md).

2,654 files, zero container parse failures, every one a 64-bit `hk_2010.2.0-r1` packfile.
Roles: 2,609 animation, 35 behavior, 4 skeleton, 3 character, 3 project.

### The class surface is enumerable

Fifty-five distinct object classes appear across the 35 behavior files. That is the
whole of what item 14.2 owes, and it is a list rather than an open question. The head of
the distribution, as `class objects files`:

```text
hkbStateMachineStateInfo 5269 35
hkbClipGenerator 4975 35
hkbClipTriggerArray 3707 35
hkbVariableBindingSet 3514 35
hkbBlenderGeneratorChild 3358 32
hkbStateMachine 1963 35
hkbStateMachineTransitionInfoArray 1895 31
hkbStateMachineEventPropertyArray 1560 35
hkbBlenderGenerator 1014 32
hkbModifierGenerator 773 28
hkbBoneWeightArray 742 28
hkbManualSelectorGenerator 473 29
BSSynchronizedClipGenerator 435 8
hkbBlendingTransitionEffect 397 30
BSIsActiveModifier 169 28
```

Three things follow.

First, the shape is dominated by five classes. State machines with their state info and
transition arrays, clip generators with their trigger arrays, blender generators with
their children, and the variable binding sets that wire them to variables account for
most of every graph. A decoder set that covers those, plus the transition effect and the
modifier generator, covers the bulk of the vanilla player graph before any long tail is
touched.

Second, **every one of the 35 graphs is rooted at an `hkbStateMachine`**, without
exception. Evaluation therefore has one entry shape to get right, not several.

Third, twelve of the 55 classes are Bethesda's own `BS*` extensions —
`BSSynchronizedClipGenerator` (435 objects), `BSIsActiveModifier` (169),
`BSiStateTaggingGenerator` (157), `BSBoneSwitchGenerator` (129),
`BSCyclicBlendTransitionGenerator` (79), and others. A decoder set covering only stock
Havok classes would leave holes in the middle of the vanilla graph, so the registry must
carry `BS*` classes as first-class entries and not as an afterthought.

### The variable and event surface is the runtime contract

301 distinct variable names and 1,985 distinct event names across the behavior files.
These are what item 14.5 binds engine state to, and they are named rather than numbered,
which is what makes the binding readable: `bAnimationDriven`, `iSyncSprintState`,
`SpeedSampled`, `Direction`, `IsFirstPerson`. `mt_behavior.hkx` alone declares 67
variables and 931 events.

The declared types confirm the decode independently. Bethesda's naming convention makes
the check free: `b*` variables decode as bool, `i*` as int32, and the blend and speed
variables as real, in every file.

### The two behavior sets are peers

`defaultmale.hkx` and `defaultfemale.hkx` each name one character file, which names
`Behaviors\0_Master.hkx`; `_1stperson\firstperson.hkx` does the same for
`_1stperson\characters\firstperson.hkx`, which names its own `Behaviors\0_Master.hkx`
under the first-person tree. 18 third-person behavior files against 17 first-person ones.
This is the concrete basis for putting first person in scope: the data is already there
and already complete, so the cost is running the evaluator twice, not writing a second
system.

The third-person character file lists 1,656 animation clips and the first-person one 869.
That is the clip surface the graph selects from, and it is the reason clip loading has to
go through the character file's list rather than through path guessing.

### Container risk did not materialise

The scope warned that a tagfile among the vanilla behavior files would mean writing a
second container parser, and asked for a stop-and-re-scope if one appeared. None did. All
2,654 files are packfiles of the version M6 already parses, and the sweep asserts that
rather than assuming it, so the claim stays enforced rather than remembered.

## What 14.1 delivered

Shared object-graph resolution — `HKXObjectGraph`, `HKXObjectCursor` — so a class decoder
declares member offsets and reads through one API instead of rebuilding fixup
dictionaries. The three existing decoders were reworked onto it with no behavior change
and their tests unchanged, which is what proves the API rather than asserting it. The
graph-level classes (root container, `hkbBehaviorGraph`, graph data, string data,
variable value set, project and character string data) and the census itself round it out.

The resolution contract is the part worth restating, because 14.2 multiplies it across
dozens of classes: **an unresolvable field yields nil and a recorded reason, never a
trap.** Malformed input costs one field, not the load. A `noFixup` miss is Havok's null
optional and is expected; every other reason means a decoder read the wrong bytes, and
the real-data sweep asserts there are none of those across the whole install. Two
`noFixup` misses occur in vanilla, both `m_ragdollName` on the first-person character
files, which have no ragdoll.

## Out of scope

Node and modifier classes are 14.2 (#329) and evaluation is 14.3 (#187) and 14.4 (#330);
this item deliberately decodes no node. `hkaAnnotationTrack` and root-motion extraction
belong to the 14.5 bridge. Ragdoll and physics classes are M15. Tagfile support is not
needed and will not be written speculatively.

## Residual risk

- **The census bounds the vanilla surface, not the modded one.** A behavior mod can
  introduce a class none of the 55 covers. The registry must therefore treat an unknown
  class the way the resolution layer treats an unresolvable field: log it, tally it, and
  degrade that node, rather than fail the graph. This is the same posture the
  [AS2 runtime scope](/decisions/swf-as2-scope.md) took for unimplemented host APIs, and
  for the same reason.
- **Decoding a class is not evaluating it.** 55 correct layouts do not imply correct
  blend weights or correct transition timing, and no measurement here speaks to that.
  Evaluation carries its own uncertainty and its own gate.
- **Layout sources are reimplementations, not a specification.** They agree with each
  other and with the observed bytes for the graph-level classes, which is real evidence,
  but a node class where they disagree needs a probe before it is trusted.
- **Runtime cost is unmeasured.** `mt_behavior.hkx` alone holds 5,115 objects, and
  nothing yet indicates how much of a graph is walked per frame.

## References

- [HKX behavior graph objects](/formats/hkx-behavior.md) — the byte layouts and the full
  census figures this document draws on.
- [HKX packfile container](/formats/hkx-container.md) — the container these objects live
  in.
- [hkaSkeleton](/formats/hka-skeleton.md), [hkaSplineCompressedAnimation](/formats/hka-animation.md)
  — the rig and clip layers the graph selects between.
- [AS2 runtime scope](/decisions/swf-as2-scope.md) — the precedent for scoping a large
  clean-room reverse-engineering effort by measuring the vanilla surface first.
- [CLI tools](/tools/cli.md) — `openskycli hkx`, the per-file census.

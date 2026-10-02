---
type: Decision
title: Havok behavior graph scope for player locomotion
description: Reimplement the Havok Behavior graph in full over the class set the vanilla player
  files use, instead of approximating it with a native state machine - swim included, first person
  with full arms, and a clean-room sourcing rule - with the census that bounds it.
tags: [decision, havok, hkx, behavior, animation, locomotion]
---

# Havok behavior graph scope

Binding for the behavior graph decoders, the evaluator, the runtime bridge that drives the player,
and any later work that animates a creature.

## Context

The direction was to reimplement Havok Behavior graphs, for vanilla movement feel and for animation
mod compatibility, instead of a native state machine of our own. This page says what "reimplement"
covers, and it was written after measuring the vanilla files.

The packfile container ([HKX container](/formats/hkx-container.md)), `hkaSkeleton`
([hkaSkeleton](/formats/hka-skeleton.md)), and clip sampling
([hkaSplineCompressedAnimation](/formats/hka-animation.md)) give a rig and a clip. Nothing chose which
clip, or blended two of them. That is all a behavior graph does.

## Decision

Every node class in the vanilla player behavior files gets a decoder, and the evaluator walks a class
registry, not a hand-written switch over the few classes locomotion needs. Decoding the graph's
variables and events but choosing clips in custom Swift was rejected, because it makes every
animation mod a special case, which is what the direction was meant to avoid.

Swim is in scope. It is a locomotion state in the same graph as walk, run, and sprint. Leaving it out
would ship a player who moves correctly until they step into a river.

First person is in scope with full arms, not a camera mode with the third-person graph behind it.
The install ships a complete parallel set under `_1stperson\`: its own project file, character file,
and 17 behavior files. The census shows it is a peer of the third-person set, not a subset
([first person](/engine/first-person.md)).

Sourcing is clean-room. Class layouts come from independent open-source reimplementations,
ret2end/HKX2Library (MIT), soulsmods/DSMapStudio HKX2 (MIT), and exyorha/hkxparse (MIT), and from
bytes observed in the user's own files. No Havok SDK headers, no decompiled or leaked source, and no
Creation Kit or SKSE internals. Each layout is checked against the install before it is documented,
and the documentation names the project the offsets came from. This is the project's normal rule,
repeated here because behavior classes are the largest body of Havok layout the project
reimplements.

Evaluation is the goal. Ragdoll and physics classes next to behavior data are separate work
([ragdoll](/engine/ragdoll.md)).

## Evidence: the census

The numbers come from a real-data census of every `.hkx` under `meshes\actors\character\`. The full
report is derived from game content, so it stays in `logs/`. Run it with
`make test-real T='HKBBehaviorCensusRealDataTests/censusesCharacterBehaviorFiles()'`, or inspect one
file with `openskycli hkx <key>`. The layouts are on the
[HKX behavior graph objects](/formats/hkx-behavior.md) page.

There were 2,654 files with no container parse failure, every one a 64-bit `hk_2010.2.0-r1`
packfile: 2,609 animation, 35 behavior, 4 skeleton, 3 character, and 3 project files.

### The class set is a list

55 object classes appear across the 35 behavior files. That is all the decoders owe. The most
common, as `class objects files`:

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

Three things follow:

- Five groups make up most of every graph: state machines with their state info and transitions,
  clip generators with their triggers, blender generators with their children, and the variable
  bindings that wire them to variables. Those, plus the transition effect and the modifier
  generator, cover most of the vanilla player graph.
- Every one of the 35 graphs is rooted at an `hkbStateMachine`, so evaluation has one entry shape.
- 12 of the 55 classes are Bethesda's own `BS*` extensions, such as `BSSynchronizedClipGenerator`,
  `BSIsActiveModifier`, `BSiStateTaggingGenerator`, `BSBoneSwitchGenerator`, and
  `BSCyclicBlendTransitionGenerator`. They sit in the middle of the vanilla graph, so the registry
  treats them as first-class entries.

### Variables and events are the runtime contract

There are 301 distinct variable names and 1,985 distinct event names. The engine binds its state to
these, and they are names, not numbers, which keeps the binding readable: `bAnimationDriven`,
`iSyncSprintState`, `SpeedSampled`, `Direction`, `IsFirstPerson`. `mt_behavior.hkx` alone declares
67 variables and 931 events. The declared types check the decode for free, through Bethesda's naming:
`b*` variables decode as bool, `i*` as int32, and the blend and speed variables as real, in every
file.

### The two behavior sets are peers

`defaultmale.hkx` and `defaultfemale.hkx` each name one character file, which names
`Behaviors\0_Master.hkx`. `_1stperson\firstperson.hkx` does the same for
`_1stperson\characters\firstperson.hkx`, which names its own `Behaviors\0_Master.hkx`. There are 18
third-person behavior files and 17 first-person ones. So first person costs running the evaluator
twice, not writing a second system.

The third-person character file lists 1,656 clips and the first-person one 869. Clips are loaded
through the character file's list, not by guessing paths.

### No tagfiles

A tagfile among the vanilla behavior files would have needed a second container parser. There is
none: every file is a packfile of the version already parsed, and the census asserts it.

## The resolution contract

A class decoder declares member offsets and reads through one object graph API. An unresolvable field
gives nil and a recorded reason, never a trap, so bad input costs one field, not the load. A
`noFixup` miss is Havok's null optional and is expected. Any other reason means a decoder read the
wrong bytes, and the real-data sweep asserts there are none across the install. Vanilla has two
`noFixup` misses, both `m_ragdollName` on the first-person character files, which have no ragdoll.

## Residual risk

- The census bounds the vanilla set, not the modded one. A behavior mod can add a class none of the
  55 covers. So an unknown class is logged, counted, and degrades its node, and the graph does not
  fail. This is the same stance the [AS2 scope](/decisions/swf-as2-scope.md) took for unimplemented
  host APIs, for the same reason.
- Decoding a class is not evaluating it. Correct layouts do not prove correct blend weights or
  transition timing.
- The layout sources are reimplementations, not a specification. They agree with each other and with
  observed bytes for the graph-level classes, but a class where they disagree needs a probe first.
- `mt_behavior.hkx` alone holds 5,115 objects, so the cost of walking a graph each frame matters.

## References

- [HKX behavior graph objects](/formats/hkx-behavior.md) and
  [behavior node classes](/formats/hkx-behavior-nodes.md): the layouts and census figures.
- [Behavior runtime](/engine/behavior-runtime.md): how the graph is evaluated.
- [CLI](/tools/cli.md): `openskycli hkx`, the per-file census.

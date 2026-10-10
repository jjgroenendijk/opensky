---
type: Subsystem
title: Object animation
description: How traps, doors, and levers run the Havok behaviour graph their mesh names, and
  how Papyrus drives it.
tags: [engine, animation, behavior, scripting, app-ui]
---

# Object animation

A swinging blade, a Nordic door, or a lever moves through a Havok behaviour graph, the same
kind of graph the player runs ([behaviour runtime](/engine/behavior-runtime.md)). Its mesh
names the graph, and its script raises the graph's events.

## Finding the graph

A cell build looks only at `ACTI` and `DOOR` references. Their mesh may hold a
`BSBehaviorGraphExtraData` block ([NIF](/formats/nif.md#bsbehaviorgraphextradata)). It
names a project file under `meshes\`. The rest of the set is read relative to the project's
folder:

| File | Read from | Example for `trapbladeswinging01.hkx` |
| --- | --- | --- |
| Project | `hkbProjectStringData` character list | `characters\character00.hkx` |
| Character | `hkbCharacterStringData` behaviour, rig, clips | `behaviors\behavior00.hkx` |
| Rig | `hkaSkeleton`, one bone per moving part | `characterassets\trapbladeswinging01_skeleton.hkx`, bone `Blade01` |
| Clips | the character's animation names | `animations\trapbladeswinging01_trigger.hkx` |

Confirmed on the install: about 40 object projects, among them the traps, Nordic doors,
portcullises, levers, and Dwemer machines. The blade's graph declares the events `Loop`,
`Reset`, `Single`, `Off`, and `Apex`.

The build decodes the set on the build queue and keeps it per project. A failed set is logged
once and the object stays static.

## Drawing the moving part

Each moving part is a node of the mesh with the same name as a rig bone. The build loads the
reference its own copy of the mesh, and binds each shape below such a node to that node. The
shape's transform becomes relative to the node, so at the node's rest transform the shape
draws where the file put it. A shape under no rig bone stays still. The math is the one a
weapon uses ([actor resolution](/engine/actor-resolution.md)).

The copy is per reference, because each object poses its own skinning palette. Its pose
comes from a pose buffer, the same one the player body reads.

## Running the graph

`ObjectBehaviorCoordinator` runs on the main actor in the world update. In reference order it
starts a graph for each new object, drops the graphs of departed cells, steps each graph, and
publishes its bones. Clips load off the main actor and arrive at the next step.

An object never walks, so no bone is a root whose travel is taken out of the pose. A rebuilt
cell brings a new pose buffer, and its object starts again at its first state.

## Papyrus

| Native | With a graph | Without a graph |
| --- | --- | --- |
| `PlayAnimation(event)` | Raises the event, answers true | Answers true at once |
| `PlayAnimationAndWait(event, done)` | Raises `event`, waits until the graph fires `done` | Answers true at once |
| `WaitForAnimationEvent(done)` | Waits until the graph fires `done` | Waits one second, answers true |
| `PlayGamebryoAnimation` | Answers true at once | Answers true at once |

A wait ends with true when the event fires, and with false when the object's cell unloads.
Every event a graph fires also reaches `OnAnimationEvent` of the scripts that registered
for it. `PlayAnimation` of an event the graph does not declare falls back to the answer
without a graph, so a script never waits for an event that cannot come.

## Where OpenSky differs

- `BGSGamebryoSequenceGenerator` has no decoder. A graph state that plays one holds the last
  pose. The blade project has three.
- Tagfile (`.hkt`) projects are not read, so the activators and the ballista that ship as
  tagfiles stay static.
- The moving part has no collision body. A swinging blade does not hit; the trigger volume
  does.
- `FURN`, `CONT`, and `MSTT` references are not checked for a graph.

## Controls

World > World > Animated Objects lists the running objects with their project, state, and
events. It sends a chosen event, as a script's `PlayAnimation` does, and switches all object
animation off. The switch is also on the launcher's Graphics page.

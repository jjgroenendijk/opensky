---
type: Subsystem
title: Object animation
description: How traps, doors, and levers run the Havok behaviour graph their mesh names, how
  doors without a graph play their mesh's Open and Close sequences, and how Papyrus drives both.
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
| `Debug.SendAnimationEvent(ref, event)` | Raises the event on `ref` | Does nothing |
| `GetAnimationVariableBool`, `Int`, `Float` | Reads the graph variable | Fails |
| `SetAnimationVariableBool`, `Int`, `Float` | Writes the graph variable | Fails |

A wait ends with true when the event fires, and with false when the object's cell unloads.
Every event a graph fires also reaches `OnAnimationEvent` of the scripts that registered
for it. `PlayAnimation` of an event the graph does not declare falls back to the answer
without a graph, so a script never waits for an event that cannot come.

A variable read or write converts between the graph's type and the type the native names,
as a Papyrus cast does: true is 1, and any number other than 0 is true. A variable the graph
does not declare fails the native, so the script gets the default value.

## Where OpenSky differs

- `BGSGamebryoSequenceGenerator` has no decoder. A graph state that plays one holds the last
  pose. The blade project has three.
- Tagfile (`.hkt`) projects are not read, so the activators and the ballista that ship as
  tagfiles stay static.
- The moving part has no collision body. A swinging blade does not hit; the trigger volume
  does.
- `FURN`, `CONT`, and `MSTT` references are not checked for a graph.

## Sequence doors

Most doors have no behaviour graph. Their mesh moves its leaves with two
`NiControllerSequence` blocks named `Open` and `Close` ([NIF sequences](/formats/nif-sequences.md)).
Each sequence has one transform track per leaf node, and text keys such as
`0.0 Sound: DRSWoodGateHelgenOpen`. The name after `Sound:` is the editor ID of an `SNDR`.
Confirmed on the install: the Helgen gate `Clutter\Helgen\HelgenGate01.nif` moves `DoorLeft`
and `DoorRight` over 4 seconds, and Solitude, Windhelm, Riften, Markarth, and Dwemer doors use
the same two names.

A cell build treats a `DOOR` reference as a sequence door when it has no `XTEL` teleport, its
mesh names no behaviour graph, and its mesh has both sequences. Like an object with a graph, it
draws its own node-skinned copy, with one root bone per leaf node.

The open state is the reference's activation state in the world state, so a save keeps it.
`ONAM` ("Open by Default") starts it open. The use key toggles it, unless the door is locked
or its activation is blocked. `SetOpen` writes it, and `SetOpen(true)` also unlocks the door
([SetOpen](https://ck.uesp.net/wiki/SetOpen_-_ObjectReference)).

`SequenceDoorCoordinator` follows that state on the main actor, in reference order:

- A door that loads is placed at the end of its open or close sequence, with no sound.
- A changed state plays the other sequence. A door that turns back part way starts the other
  sequence as far from its end as it was from its start.
- Each text key the sequence passes goes to the animation event coordinator, which plays
  `Sound:` keys ([animation events](/engine/animation-events.md)).
- A rebuilt cell brings a new pose buffer. The door keeps its motion and poses the new buffer.

`GetOpenState` answers 1 open, 2 opening, 3 closed, or 4 closing
([GetOpenState](https://ck.uesp.net/wiki/GetOpenState_-_ObjectReference)). A door told to move
answers opening or closing at once, before its next step.

The cell build takes each sequence door's collision out of the static set. It places the
door's solid bodies again and groups them by the leaf their node moves with. Each collision
query moves a leaf's shapes by the leaf's move from rest, so an open gate does not block the
path. A body on no leaf, such as a frame, stays where it is.

### Where OpenSky differs for sequence doors

- A load door does not play its sequences; the use key starts the transition.
- `GetOpenState` answers 1 or 3 for any other reference, where the game answers 0 for a
  reference that cannot open.
- Text keys reach Papyrus `OnAnimationEvent` only through the graph path, not from sequence doors.

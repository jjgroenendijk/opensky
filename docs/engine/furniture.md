---
type: Subsystem
title: Furniture
description: How the player and package actors sit in chairs and lie in beds - the seats a
  FURN reference has, which seat an actor takes, standing up, and the furniture natives.
tags: [engine, furniture, packages, papyrus]
---

# Furniture

A piece of furniture is a `FURN` reference. An actor uses one of its seats: it sits on a
chair, lies in a bed, or leans on a wall. The player uses a chair by activating it. A Sit or
Sleep package uses its target the same way. One ledger of seats serves both, so two actors
never share a seat.

## Seats

A furniture mesh marks each seat with its `BSFurnitureMarkerNode` block
([NIF](/formats/nif.md#bsfurnituremarkernode)). Each marker gives a position, a heading, an
animation type (1 sit, 2 sleep, 4 lean), and the sides an actor may enter from (1 front,
2 behind, 4 right, 8 left, 16 up). The `FURN` record changes the markers
([UESP "Skyrim Mod:Mod File Format/FURN"](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/FURN)):

| Field | Meaning |
| --- | --- |
| `MNAM` bits 0 to 23 | The markers the record uses. A marker whose bit is clear is no seat |
| `ENAM` | A marker index; the `NAM0` and `FNMK` after it belong to that marker |
| `NAM0` | Entry sides the record turns off for the marker (the second `uint16`) |
| `FNMK` | A keyword. Only an actor whose base `NPC_` has it (`KWDA`) may use the seat |

`MNAM` matters for double beds. `CommonBedDouble01L` (`000F5101`) has `MNAM` `0x88000001`
and `CommonBedDouble01R` (`000F5102`) has `0x88000002`: both use the double bed mesh, and
each record turns on one side. Observed in `Skyrim.esm`: of the 400 uncompressed `FURN`
records, 18 two-marker records turn on only one marker. `NAM0` is rare. `ExecutionerChoppingBlock` (`0002E8EB`)
turns off the right side of marker 0.

## Which seat an actor takes

The ledger picks a free seat by these rules, in order:

- A switched-off seat, a seat held by another actor, and a keyed seat the actor lacks the
  keyword for are never taken.
- A keyed seat the actor has the keyword for comes first.
- A seat of the wanted animation type comes next: sleep for a Sleep package, sit for a Sit
  package. The player and `debug sit` want no type.
- Among equal seats, the one nearest the actor wins.

Example: `ExecutionerChoppingBlock` has three markers. Marker 0 has the keyword
`isExecutioner` and marker 2 `isExecutionerGuard`; marker 1 has none, so the prisoner gets it.
The keyword rule is OpenSky's reading of the record.

A package reserves its seat when its procedure starts, before the actor walks there. Leaving
the package frees the seat, even when the actor never sat down.

## Sitting down and standing up

On arrival the actor's root is set below the seat's point, at the furniture's own height,
facing the marker heading plus the reference's own z rotation. The marker itself sits on the
seat, but the furniture clips put the root on the floor. Observed on the install:

| Data | Height |
| --- | --- |
| `CommonChair02L` reference `000914E3` (Bannered Mare), its origin | floor |
| Its marker | 34 above the origin |
| `NPC COM` in `male\chair_idlebasevar1.hkx` | 39 above the clip root |
| `NPC COM` in `bed_leftsleep.hkx` | 53 above the clip root |
| `NPC COM` in `bedroll_leftsleep.hkx` | 18 above the clip root |
| `NPC COM` standing, first frame of `bed_leftenter.hkx` | 69 above the clip root |
| `WoodenBarStool.nif` marker, and `NPC COM` in `aobarstoolidle.hkx` | 49, and 55 |
| `WindhelmThrone.nif` marker, and `NPC COM` in `special_jarlchairidlecrossarm.hkx` | 34, and 39 |
| `SitLedgeMarker.nif` marker, and `NPC COM` in `idlesitledge.hkx` | 0, and 8 |
| `CounterLeanMarker.nif` marker, and `NPC COM` in `idleleantable.hkx` | 32, and 69 |

Every seat clip puts the hips about 5 units above its marker, with the clip root on the
floor; a lean clip stands on the floor. So a seated body on the marker would float one seat
height above the chair. Dropping the marker's own z offset is OpenSky's reading of that
data; no source states the rule. `openskycli nif <mesh>` prints a mesh's markers.

The actor's entry side is the allowed side that faces where it stood. The idle runtime then
plays the entry idle that the `ActionActivate` tree picks for the marker
([idles](/engine/idle-runtime.md)), and the actor's scripts get `OnSit`. An NPC also
activates the furniture, so the furniture's scripts get `OnActivate`. The player's own
activation already sends that event.

The seated player's body root goes on the seat's root, and the eye goes on the seat idle's
head bone, as on a [cart seat](/engine/vehicles.md). After the entry clip ends, the eye stays
where that clip left the head. The seat holds the player while no clip plays, because a
walking step there would drop the player and the graph would leave the seat state. On sitting
down, the first-person view turns the way the seat faces.

A move key or the jump key gets the player up. A package actor gets up when its package
ends. The actor then reads `GetSitting` 4, and the `ActionActivate` tree picks the exit idle,
such as `ExitChair`. Scripts get `OnGetUp`.

Clips carry no root motion; the project's [animation data](/formats/animation-data.md) does.
An entry clip ends on the seat, so the actor starts where its motion leads back from: 52
units left of a chair for `Chair_LeftEnter`. An exit clip starts on the seat and carries the
actor out: 52 units to the left for `Chair_LeftExit`. While the exit plays, the player's
input does nothing and an NPC's next package waits. When it ends, the actor stands where the
motion left it and faces its way. An exit clip without motion data leaves the actor
`FurnitureSeat.standDistance` (48 units) out on the entry side, or on the root for the up
side.

A teleport or a cell change that takes the seated or rising player more than 256 units from
the seat, or unloads the furniture, also ends the seat, without an exit idle.

A bed that the player activates opens the rest menu instead ([sleep and wait](/engine/sleep-wait.md)),
and a crafting station opens its menu. A chair has a workbench field too, of type none, so it
is furniture.

The launcher's "Sit in furniture" switch turns the feature off. Then a chair does nothing, and
a Sit or Sleep package actor stands at its seat.

## Record flags

The meanings come from the Creation Kit wiki page
<https://ck.uesp.net/wiki/Furniture>, and the bits from
[UESP "Skyrim Mod:Mod File Format/FURN"](https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/FURN).
Counts are from the 400 uncompressed `FURN` records of `Skyrim.esm`.

| Flag | OpenSky |
| --- | --- |
| Header `0x20000000` Child Can Use | A child actor (race flag) takes only furniture with it |
| Header `0x10000000` Must Exit To Talk | A seated NPC stands up when the player starts dialogue with it. Always paired with `MNAM` `0x08000000` |
| `MNAM` `0x04000000` Is Perch | Only an actor whose race has `ActorTypeDragon` uses it, and a dragon uses nothing else |
| `MNAM` `0x02000000` | The player cannot activate it |
| `FNAM` `0x02` Ignored By Sandbox | A sandbox does not choose the furniture ([sandbox](/engine/sandbox.md)) |
| `NAM1` Associated Spell | Added to the actor when it sits, removed when it gets up. No vanilla record has one |

`MNAM` `0x40000000` and `0x80000000` are set on most records. No source names them, and
OpenSky does not use them. `FNPR` lists each marker's animation type and entry points; on
the meshes checked it repeats the mesh marker (`WoodenBarStool`: sit, behind), and OpenSky
reads the mesh.

## Papyrus

| Native | OpenSky |
| --- | --- |
| `ObjectReference.IsFurnitureInUse(abIgnoreReserved)` | True when an actor holds any marker. With `abIgnoreReserved`, only an actor that sits counts |
| `ObjectReference.IsFurnitureMarkerInUse(aiMarker, abIgnoreReserved)` | The same for one marker |
| `Game.SetSittingRotation(afValue)` | Turns the seated player's first-person view `afValue` degrees from the seat's facing; negative looks left. It lasts until the player stands up |

The signatures and meanings come from the Creation Kit wiki pages of the same names, for
example <https://ck.uesp.net/wiki/IsFurnitureInUse_-_ObjectReference>. The wiki says
`SetSittingRotation` does nothing in third person; OpenSky follows that. When the game resets
the rotation is not documented; resetting it on standing up is OpenSky's choice.

## Checking it in the game

`openskycli game debug sit [<ref>] [--furniture <ref>]` seats the player or an NPC in the
given furniture, or in the nearest loaded one with a free seat. `debug stand [<ref>]` gets it
up. `state furniture [<ref>]` reads an actor's sit state, seat, entry side, and position, or
a piece of furniture's markers with their point, root, and holder.

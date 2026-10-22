---
type: Subsystem
title: Interaction targeting
description: How the use key picks a target along the view ray, what each record type offers,
  who hears an activation, how items are taken and dropped, and how the HUD shows the target.
tags: [engine, interaction, collision, streaming]
---

# Interaction targeting

The use key (F) has one path shared by doors, containers, activators, items, and actors. The
current target under the crosshair is a value. Pressing F sends one typed event. The HUD, sound,
scripts, and doors all listen to that event. None of them picks targets on its own.

## What can be used

When the cell builder builds a cell, it records for each usable reference: the `REFR` and base
FormIDs, the position, a name (base `FULL`, then `EDID`, then the FormID), and an action.

| Base | Action |
| --- | --- |
| `DOOR` | Open |
| `CONT` | Search |
| `ACTI` | Activate. `RNAM` replaces the word |
| `TREE` | Harvest |
| `FLOR` | Harvest. `RNAM` replaces the word |
| `TACT` | Talk |
| `FURN` | Activate. A bench with `WBDT` also opens a [crafting](/engine/crafting.md) session |
| `MISC`, `WEAP`, `AMMO`, `ALCH`, `INGR`, `BOOK`, `KEYM`, `SLGM`, `APPA` | Take |

`FULL` and `RNAM` are lstrings, so a localized plugin reads them from its string table. The
action words are English for now. Localized words from game settings come later.

`ARMO` is not takeable yet, although it can be carried. Its world model is `MOD2` or `MOD3`, and
its worn pieces come through `ARMA`, not one `MODL`. That needs the equipment work.

Not usable: `MSTT`, an `ACTI` with "ignore object interaction", an automatic `DOOR`, and a `FURN`
whose marker flags turn off activation. The fields are on the
[world records](/formats/world-records.md) page.

## Picking a target

The game view gives a view ray only in walk mode. In fly mode it gives none, which clears the target
and makes F do nothing. The ray is normalized, finite, and 192 units long.

The broad phase searches the loaded static collision trees with the ray's bounds. The exact test
checks triangle meshes, convex faces, boxes, spheres, and capsules, after moving the ray into each
shape's local space. The ray keeps its original parameter through that move, so distances stay
right under rotation and uneven scale. Equal distances go to the lower `REFR` FormID.

The nearest collision hit is found first, and only then is its usable data looked up. So a wall
hides an activator behind it. This also means an object with no solid collision cannot be targeted
yet.

Actors are not in the collision trees. A second test checks the view ray against actor capsules,
and an actor becomes a normal target with the action "Talk". The nearest solid hit still blocks
it: an actor counts only if it is nearer than any geometry on the ray. See
[dialogue menu](/engine/dialogue-menu.md).

## Activation

A target change publishes the target, the exact hit point, and the distance. F publishes one event
for the current target.

The event goes to several listeners, in the order they registered:

1. World sound plays the activation sound.
2. The Papyrus bridge records the activation and queues `OnActivate`.
3. World items take the object, if it is takeable.

Each is a separate result of the same event. Scripts listen beside the engine's own behavior and
never replace it.

The event carries a FormID, which depends on the load order. The Papyrus listener turns it into a
session-stable `ReferenceKey` through the loaded cells. An event for a reference no loaded cell knows
is dropped, not recorded under a guessed identity. See [Papyrus
activation](/engine/papyrus-activation.md) and [runtime state](/engine/runtime-state.md).

Activating an actor also sends a talk event with the speaker's `ReferenceKey`, because dialogue and
saves name a speaker that way. It fires after the normal event. So sound and scripts see an actor
activation exactly like a door activation, before any menu opens. A `TACT` talking activator
sends the same talk event, with its own reference as the speaker and the base's `VNAM` voice
type ([world records](/formats/world-records.md)).

A door with the "Open" action asks for a transition for that exact reference. With an `XTEL` it
follows the [interior](/engine/interiors.md) path. Without one, it still sends the event, but has
no open animation yet.

A bed is a `FURN` whose model has a sleep marker (animation type 2). Its prompt reads "Sleep",
and using it opens the [rest menu](/engine/sleep-wait.md).

### Automatic doors

A `DOOR` with `FNAM` bit 0x02 ("Automatic") opens when the player walks into it, not with the
use key. The Creation Kit wiki page "Door" (<https://ck.uesp.net/wiki/Door>) says it is
activated when the player enters its space. OpenSky takes that space as the base's `OBND` box
at the reference's position, rotation, and scale. A door without bounds is left out. The door
fires once when the feet enter the box, and again only after they leave it. The crosshair
never picks an automatic door. In `Skyrim.esm` the automatic doors are the
`AutoLoadDoor01` family, invisible load doors at the mouth of some caves.

### Activate parents

A reference with `XAPR` children passes its activation on to them
([Papyrus activation](/engine/papyrus-activation.md)). Each child has a delay in seconds
(Creation Kit wiki "Reference", <https://ck.uesp.net/wiki/Reference>). A child with a delay
above 0 activates once that many seconds of world time have passed, so a menu pause holds it.
A reference with `XAPD`
"Parent Activate Only" can be activated only by its parent or a script: it has no use-key
target.

## Locks

A door or container with `XLOC` lock data passes through the lock gate before any listener
hears the press. A carried key unlocks it and the press goes on. A pickable lock opens the
lockpicking menu instead; a "requires key" lock refuses. The prompt reads "Unlock" and the
name gains the difficulty, such as "Chest (Adept)". See [locks](/engine/locks.md).

## Taking and dropping

World items need no menu. Taking an object is a world change. The panel buttons and the menus call
the same three operations as the use key. Each is one world state write, so the change log, the cell
rebuild, and the save all see it with no extra work.

| Operation | Inventory | World |
| --- | --- | --- |
| Take | Add to the player | A plugin object is marked deleted. A spawned object is removed completely |
| Drop | Remove from the player | A new spawned object with a new generated key |
| Container transfer | Move both ways | Nothing. Only items move |

In each operation the inventory math runs first, and can fail. The world write happens only after
it succeeds. So a take that would overflow the player's stack leaves the item in the world. It does
not delete it into nowhere.

A reference stands for `XCNT` items, or its spawned count, or one. An `XCNT` of 0 or less counts as
one, because an object in the world is at least one item.

A spawned object is removed completely on take, not marked deleted. It exists only because the world
state says so. Dropping that state removes it, and leaves nothing behind to fill every later save.

## Containers

A container session is a live view of one container, not a copy. Its contents are read again on
every access, so a script that empties the chest during the session shows up at once. Each transfer
moves all or nothing. "Take all" is not all-or-nothing across stacks. A later stack can only fail
by overflowing a player stack of over two billion, and stopping there is better than refusing to
empty the chest.

The session sets the container's "open" state when it starts and clears it when it ends. The Papyrus
bridge toggles "open" for doors, because one activation is one swing. A container is open for as
long as its session lasts, and only the session knows that.

## Harvesting

Activating a `FLOR` or `TREE` reference adds its `PFIG` produce to the player inventory and sets
a harvested component on the reference. A produce that names an `LVLI` gives the list's
deterministic pick, as container baselines do. A harvested reference shows `Harvested` in place
of the action word, and activating it does nothing. The component is saved in the `HRVS` and
`HRVD` chunks ([OpenSky save](/formats/opensky-save.md)).

Each harvest rolls the plant's `PFPC` chance for the season of the game date. The CK wiki says
the produce is given "depending upon the harvest chance set for that season"
([Flora](https://ck.uesp.net/wiki/Flora)). A failed roll gives nothing, and the plant still reads
as harvested. The seasons follow the Tamriel months in
[UESP Lore:Calendar](https://en.uesp.net/wiki/Lore:Calendar): spring is First Seed to Second
Seed, summer is Midyear to Last Seed, fall is Hearthfire to Sun's Dusk, and winter is Evening Star
to Sun's Dawn. Six vanilla plants, such as `ChickenNest`, have 0 in every season. They still give
produce in the game, so a plant with no chance in any season always yields. Without a game clock
the roll is skipped. Mod Ingredients Harvested ([perk entry points](/engine/perk-entry-points.md))
sets how many times a yield is granted.

## Grow back

A harvested plant grows back when its cell resets ([cell reset](/engine/cell-reset.md)): the
player leaves the cell, stays away for `iHoursToRespawnCell` game hours, and comes back. The
install has 240 hours, which is 10 game days.

World > Inventory & Equipment > Harvest shows the wait for the plant under the crosshair. Its
`Grow back` button makes the one plant grow back now. World > Runtime State makes every cell
reset due.

## Where a drop lands

A dropped object lands one step in front of the camera and one standing height below it. These are
fixed offsets, not physics. The forward direction is flattened to the ground first, so looking at the
sky does not throw the item behind the player. A camera looking straight up or down puts the item
right below the eye. The object belongs to the interior if one is open, or else to the exterior cell
at the grid center.

How a spawned object is named, built, and saved is on the [runtime state](/engine/runtime-state.md)
page.

## HUD

The vanilla `hudmenu.swf` bridge listens for target changes. It only stores the new target. The
renderer applies the prompt, compass marker, and heading together between frames.

The prompt is the action word and the name, for example `Open <door name>`. The action word is a
string setting, chosen at run time:

| Target | Setting |
| --- | --- |
| An item or a container that is not the player's to take | `sSteal`, `sStealFrom` |
| A book | `sRead` |
| An actor while the player sneaks | `sPickpocket` |
| A bed, a seat, other furniture | `sFurnitureSleep`, `sSit`, `sActivate` |
| Anything else | `sTake`, `sSearch`, `sOpen`, `sHarvest`, `sTalk`, `sActivate` |

The steal texts carry their own red `<font>` markup, which the HUD movie's crosshair text field
shows. An `ACTI` with its own `RNAM` verb keeps it. Lock and harvest labels apply on top.

The compass marker is at the reference's position, not the hit point, so it stays steady while
the ray moves over the object. No target hides the prompt and removes the marker. The HUD only
listens. It is not a second interaction system.

## Controls

World > HUD & Interaction:

- Target: shows the `REFR` and base FormIDs, action, name, distance, positions, the exact prompt sent
  to the movie, and the headings. It only shows live values. It has no fake target that could hide a
  real failure.
- Items: Take target, Search target, Take all, Close container, and Drop (a FormID and a count, or the
  player's first stack). The readout shows the target, the player's stacks, weight and gold, the open
  container, spawned objects, and the last result.

The Items section has no reset of its own. Takes and drops are world changes, and World > Runtime
State already resets those. Two resets would give the same changes two owners.

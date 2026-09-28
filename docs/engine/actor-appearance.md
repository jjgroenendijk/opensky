---
type: Subsystem
title: Actor appearance
description: How actor records become a drawn actor - skeleton, skin, outfit, slot masking,
  equipped items, weapon attachment, FaceGen paths, and cell streaming.
tags: [engine, actors, appearance, armor, facegen, weapon]
---

# Actor appearance

This page follows an actor from its records to its meshes. The records are on the
[actor records](/formats/actors.md), [race and class](/formats/race-and-class.md), and
[armor records](/formats/armor.md) pages. Animation is on the
[actor animation](/engine/actor-animation.md) page.

The steps:

1. The [template chain](/formats/actors.md#template-chain) picks the record for each field.
2. Visual resolution turns those fields into models.
3. Assembly loads the models and places them.
4. The cell builder adds the actor to the cell's scene.

## Visual resolution

- Skeleton: the race's `ANAM` for the actor's gender.
- Skin: the `NPC_` `WNAM`, or else the race's `WNAM`. That `ARMO` gives its armatures that fit
  the race.
- Outfit: `NPC_` `DOFT`, then the `OTFT` entries. An `ARMO` is used as it is. An `LVLI` with
  "use all" gives every entry. Any other `LVLI` gives its highest-level entry, the first one on
  a tie. This is the same rule as for `LVLN`.
- Slot mask: the slots of all equipped armor form one mask. A skin armature that overlaps the
  mask is hidden, so no body shows through clothes. The `ARMA` slots decide the overlap. If an
  `ARMA` has none, the `ARMO` slots are used.
- Race fit: an `ARMA` fits if its primary race matches, or its `MODL` list has the race.
- Gender: `MOD2` for male, `MOD3` for female. If one is missing, the other is used. Vanilla has
  male-only armatures worn by both genders, such as `StormCloakBootsAA`.
- First person: each part also keeps its `MOD4` or `MOD5` path. So the whole look can move to the
  first-person skeleton without a new walk. A part with no first-person model is dropped there.

A loop is found by the active path only, so the same item twice in one list is allowed.

A broken chain is an error: a missing race, skin, outfit, or item, or an empty or looping
leveled list. OpenSky never falls back to a naked actor in silence. A missing optional part is a
skip with a reason, such as "no compatible armature", "masked by outfit", or "no first-person
model". So every part is either drawn or explained.

## Equipped items

An actor can have a runtime set of equipped items. That set replaces the outfit chain. It does
not add to it. The starting equipped set already is the default outfit (see
[inventory and equipment](/engine/inventory-equipment.md)). Adding the two would dress an actor
again as soon as anything took clothes off. So an empty set means a stripped actor, and the
skin comes back.

Each equipped FormID becomes one of:

- An `ARMO`: a worn piece, with the same armature choice and slot mask as an outfit.
- A `WEAP` with a model: an attachment (below).
- Anything else: a skip tagged "unrenderable equipment".

An equipped set never causes an error. A broken outfit chain is bad plugin data. An equipped
item that cannot be drawn is normal game state, such as a script token.

The set comes from the world state snapshot. A change rebuilds the cell (see
[runtime state](/engine/runtime-state.md)).

## Weapon attachment

A drawn weapon is a rigid model that hangs from a skeleton bone. The bone names come from
`skeleton.hkx` (`openskycli skeleton`):

| Bone | Parent | Use |
| --- | --- | --- |
| `Weapon` | `NPC R Hand [RHnd]` | Drawn right-hand weapon |
| `Shield` | `NPC L Hand [LHnd]` | Drawn shield |
| `Quiver` | spine | Quiver |
| `WeaponSword`, `WeaponAxe`, `WeaponDagger`, `WeaponMace` | pelvis | Sheathed |
| `WeaponBack`, `WeaponBow` | spine | Sheathed on the back |

A weapon moves between its sheathed bone and `Weapon` on the `BeginWeaponDraw` and
`BeginWeaponSheathe` clip annotations, not on the key press. So the model changes bones at the
right moment in the animation. See [melee combat](/engine/melee-combat.md).

`skeleton.nif` spells the bone `WEAPON`, and the Havok skeleton spells it `Weapon`. So the bone
lookup ignores case.

A scene bakes each placement's transform when it is built, and cells are built on a background
queue. So an attachment cannot be a placement with a fixed transform. Instead the weapon model
becomes a skinned mesh with one bone, named after the attachment bone. The pose the clip already
computes then moves it.

The shader computes `world = modelMatrix * (bone * v)`, with
`modelMatrix = actorTransform * meshLocal`. The skin data is:

```text
rootParentToSkin   = inverse(meshLocal)
skinToBoneMatrices = [meshLocal]
bindPoseMatrices   = [inverse(meshLocal) * restTransform * meshLocal]

world = actorTransform * meshLocal * inverse(meshLocal) * boneWorld * meshLocal * v
      = actorTransform * boneWorld * (meshLocal * v)
```

That is the weapon placed at the bone, in the actor's space. The bind matrix uses the bone's
rest transform, so a weapon on an actor with no animation still sits in the hand.

An attachment is never culled. Its model bounds sit at the weapon's origin, not in the hand.

A rebuild in the middle of a clip does not restart it. The animation clock never resets on a
rebuild, so the new scene samples the same time as the old one.

Not done yet: shields on the back, dual-wield placement, armature texture swaps, and the
`DNAM` weapon adjust value.

## FaceGen paths

Head parts come from two places. A race's `NAM0` opens its male and female head data. `MNAM` or
`FNAM` picks the gender, and each `HEAD` names a default `HDPT`. In an `HDPT`, each `NAM0` kind
pairs with the next `NAM1` path: 0 is the race morph, 1 is the expression TRI, 2 is the
character creation morph. The `EDID` is the name of the baked `BSDynamicTriShape`.

OpenSky joins the race's defaults with the `NPC_` `PNAM` list. The TRI format is on the
[TRI](/formats/tri.md) page. Morph weights are on the [face morphs](/engine/face-morphs.md)
page.

The baked head files use the `NPC_` that supplied the traits:

```text
meshes\actors\character\facegendata\facegeom\<plugin>\<id8>.nif
textures\actors\character\facegendata\facetint\<plugin>\<id8>.dds
```

`<plugin>` is the file name of the plugin that defines the `NPC_`, in lowercase, such as
`skyrim.esm`. `<id8>` is the FormID as 8 hex digits, with the load order byte set to `00`. This
was checked against the archive listing.

The paths exist only when the race has the FaceGen head flag. Creature races have none. A
humanoid with no head parts, such as Nazeem, still has files.

## Assembly

1. Load the skeleton once. A missing skeleton is a skip.
2. Load outfit parts, then visible skin parts, then the FaceGen head. Models are cached by path
   and skeleton.
3. Place every part with the `ACHR` position, rotation, and scale. Join their bounds into one
   box.
4. If at least one body or head model loads, the actor is drawn, even if some parts failed. With
   no model at all, the actor is rejected.

The FaceGen tint path is kept for later. Today the head uses its NIF material.

## Streaming

The cell builder runs the whole chain on its serial queue: collect `ACHR` records, resolve the
template, resolve the look, assemble, and add to the cell's scene. A worldspace-persistent
`ACHR` goes to the cell that holds its position. Actor models leave with their cell. Skeletons
stay loaded.

Every actor is counted: `discovered = rendered + disabled + failed`. Disabled means the initially
disabled flag. Every failure has a reason, such as `ACHR <id>: <why>`. The cell summary and
`bench --fly-path` check that the numbers add up ([CLI](/tools/cli.md)). See also
[cell streaming](/engine/cell-streaming.md).

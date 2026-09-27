---
type: Subsystem
title: Actor resolution
description: How a placed actor becomes a rendered one — template chains, visual parts,
  equipped items, the weapon attachment, assembly, and per-cell accounting.
tags: [engine, actors, template, armor, facegen, weapon, streaming]
---

# Actor resolution

A placed actor (ACHR) names a base NPC_. Many fields of that NPC_ come from other records:
templates, the race, the outfit, and leveled lists. This page explains how OpenSky walks
those links and builds the actor's models. The record layouts are on
[actor records](/formats/actors.md) and [armor records](/formats/armor.md).

The steps run in order on the cell build queue: collect the ACHRs, resolve the templates,
resolve the visual parts, then assemble the models.

## Template chain

`ActorTemplateResolver` follows `TPLT` links. The template flags in `ACBS` decide which
record supplies each field group. The sources are the UESP NPC_ `ACBS` notes and the
Creation Kit page "Template Data".

- Traits (`0x0001`): race, gender, skin, height and weight, voice type (`VTCK`), death item,
  and head parts. `WNAM` is on the Creation Kit Traits tab, so it follows this flag. Neither
  source names `WNAM`; this is an inference.
- Stats (`0x0002`): the whole Stats tab — level, auto-calc, the health, magicka, and stamina
  offsets, speed, bleedout, and class (`CNAM`).
- Factions (`0x0004`): the `SNAM` run and `CRIF`. No open source says which flag owns
  `CRIF`. We group it with the memberships because both answer one question: is the actor a
  guard, and for whom? On the vanilla install, every NPC_ in `IsGuardFaction` has a `CRIF`
  that names a faction it is also a member of. 465 bases resolve to a crime faction.
- AI data (`0x0010`): the whole `AIDT` struct. Factions and AI data resolve in one walk,
  each on its own flag, because the hostility check reads both
  ([combat](/engine/combat.md)).
- AI packages (`0x0020`): the whole ordered `PKID` list. An empty local list is the answer
  when the flag is clear. See [package schedules](/engine/package-schedules.md).
- Base data (`0x0080`): the name and the essential, protected, and respawn flags.
- Inventory (`0x0100`): the default outfit (`DOFT`) and carried items, but not the death
  item.

The walk rules:

- Follow `TPLT` always. The flags choose fields, not links.
- A record passes a field up only while it has a `TPLT` and that field's flag is set. A set
  flag without a `TPLT` does nothing. The last record in the chain always supplies the field.
- At an LVLN, pick the entry with the highest level, and the first one on a tie. The game
  rolls against the player level; OpenSky does not yet.
- Every resolved field records which NPC_ supplied it.
- A loop, a dangling FormID, or an empty list throws an error.

### Race for stats

The race is resolved twice. The traits race is the one the renderer uses. The stats race is
the `RNAM` of the record that supplied the stats, and the starting attributes come from it.
No source says which race the game uses for the attributes when the two differ. `Skyrim.esm`
answers it. With the traits race, 61 of 4,297 auto-calc records disagree with the values in
their own `DNAM`. With the stats race, 26 disagree, and all 26 come from one stale template
(see [actor values](/engine/actor-values.md)). The records that change are the skeleton,
draugr, and creature ones, where traits and stats give different races.

## Visual parts

`ActorVisualResolver` turns a resolved appearance into models:

- Skeleton: the race `ANAM` for the gender.
- Skin: NPC_ `WNAM`, else race `WNAM`, then the ARMO, then its ARMAs that fit the race.
- Outfit: NPC_ `DOFT`, then the OTFT entries. An ARMO is used directly. An LVLI with "use
  all" gives every entry; any other LVLI gives the highest-level entry, first on a tie.
- An ARMA fits a race when its primary race matches or its extra-race list contains it.
- Model: `MOD2` for male and `MOD3` for female. If one is missing, use the other. Vanilla
  has male-only ARMAs that both genders wear (`StormCloakBootsAA`).
- First-person model: `MOD4` or `MOD5`, with the same gender fallback. A part without one is
  dropped in first person. It does not fall back to the third-person model, because that
  mesh is skinned to bones the first-person skeleton does not have
  ([behavior runtime](/engine/behavior-runtime.md)).

Slot masking: the slots of all worn ARMOs form one mask. A skin armature whose slots overlap
the mask is hidden, so no body geometry shows under clothes. An ARMA's own slots decide the
overlap; without them, the slots of its ARMO decide.

Draw order: all worn parts are sorted by ARMA priority, lowest first. Priority never hides a
part (see [armor records](/formats/armor.md)). The sort is stable, so ties keep resolution
order. It also reorders the armatures inside one ARMO. For example, Heimskr's
`ClothesMonkRobesHooded` `00107106` lists `MonkRobesAA` `000BAD04` (priority 15) before
`MonkHoodAA` `000BAD03` (priority 10). So the hood is drawn first.

A broken outfit, skin, or race chain throws an error. OpenSky never silently shows a naked
actor. A missing optional part is skipped with a reason, so every part is counted.

## Equipped items

An actor that the game has changed has an equipped set. That set replaces the `DOFT` chain.
It does not add to it, because the starting equipped set already is the default outfit. An
empty set means an undressed actor, so the skin shows again.

Each equipped FormID becomes one of three things:

- an ARMO: a worn part, with the same ARMA choice and slot masking as an outfit;
- a WEAP with a `MODL`: an attachment (below);
- anything else: a skipped part with the reason `unrenderableEquipment`.

An equipped set never throws. A script can equip a token item, and that is normal. A cell
rebuild picks up equipment changes ([runtime state](/engine/runtime-state.md)).

## Weapon attachment

A drawn weapon is a rigid model on a named bone. The bone names come from
`meshes\actors\character\character assets\skeleton.hkx`, read with `openskycli skeleton`:

| bone | parent | use |
| --- | --- | --- |
| `Weapon` (43) | `NPC R Hand [RHnd]` | drawn right-hand weapon |
| `Shield` (42) | `NPC L Hand [LHnd]` | drawn left-hand shield |
| `Quiver` (60) | spine | quiver |
| `WeaponSword`, `WeaponAxe`, `WeaponDagger`, `WeaponMace` | pelvis | sheathed |
| `WeaponBack`, `WeaponBow` | spine | sheathed on the back |

The node in `skeleton.nif` is spelled `WEAPON`, but the Havok rig spells it `Weapon`. So the
NIF bone lookup ignores case. Draw and sheathe move the weapon between the sheathed node and
the hand node on the `BeginWeaponDraw` and `BeginWeaponSheathe` clip annotations
([melee combat](/engine/melee-combat.md)).

A scene bakes placement transforms when it is built. The only transform that changes each
frame is GPU skinning. So `RigidAttachment` turns the weapon into a skinned mesh with one
bone, named after the attachment node. The actor's animation then moves it. With the shader
rule `world = modelMatrix * (bone * v)` and `modelMatrix = actorTransform * meshLocal`:

```text
rootParentToSkin   = meshLocal⁻¹
skinToBoneMatrices = [meshLocal]
bindPoseMatrices   = [meshLocal⁻¹ · restTransform · meshLocal]

world = actorTransform · meshLocal · meshLocal⁻¹ · boneWorld · meshLocal · v
      = actorTransform · boneWorld · (meshLocal · v)
```

The bind matrix uses the node's rest transform, so a weapon that is not animated still sits
in the hand. An attachment has no bounds and is never culled, because the model's bounds are
at the weapon origin, not in the hand.

An equipment change mid-animation continues the clip; it does not restart it. The animation
clock does not reset on a cell rebuild, and actors are posed before each draw.

Not done yet: shields on the back, dual-wield placement, ARMA texture swaps, and the `DNAM`
weapon adjust value.

## Assembly

`ActorAssembler` loads the models for one actor:

- Load the race skeleton once. A missing skeleton is a skipped part with a reason.
- Load outfit parts first, then the visible skin parts, then the FaceGen head. The mesh
  cache key is the path plus the skeleton.
- Place every part with the ACHR position, rotation, and `XSCL` scale. The part bounds join
  into one world box.
- An actor with at least one body or head model renders. An actor with no model fails with
  `noCoreGeometry`.

The FaceGen head paths are on [actor records](/formats/actors.md). Expression morphs are on
[face morphs](/engine/face-morphs.md).

## Streaming and accounting

`CellSceneBuilderActors` collects the ACHRs a cell owns: its persistent and temporary
children, plus, in an exterior, the worldspace-persistent ACHRs whose position is in the
cell. The resolvers are built once, on the first cell with actors. Actor meshes belong to the
cell and are freed with it; skeletons stay loaded.

Each cell counts its actors exactly:

```text
discovered = rendered + disabled + failed
```

`disabled` is an ACHR with the "initially disabled" flag. `failed` is a malformed record, a
broken chain, or an actor with no geometry. Every failure has a reason string
(`ACHR <id>: <why>`), and `failed` must equal the number of reasons. `bench --fly-path`
checks both rules ([CLI](/tools/cli.md), [cell streaming](/engine/cell-streaming.md)).

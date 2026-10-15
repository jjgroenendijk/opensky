---
type: Subsystem
title: Papyrus condition twins
description: The Papyrus natives that ask the same question as a condition function, and how
  OpenSky answers both with one implementation.
tags: [engine, papyrus, conditions]
---

# Papyrus condition twins

Many Papyrus natives ask the same question as a condition function. `Actor.GetSitState` and
the condition `GetSitting` both read how an actor uses furniture. OpenSky answers such a
native by running its condition function over the runtime condition context, so a script
and a condition always agree. The pairs come from matching the Creation Kit wiki pages of
the native and the function.

## How a native runs its twin

- The receiver is the condition's subject. A native on a form that is not a reference, such
  as `Location.IsLoaded`, runs on the player and passes the receiver as parameter 1.
- An object argument becomes a load-order FormID. The condition context gets an identity
  translation over the load order, so the function resolves the FormID back to the same
  form. `None` passes 0, which the functions read as "any".
- The value becomes the native's return type: `Bool` is "not 0", `Int` drops the fraction.
- A function that cannot answer, for example with no furniture data, makes the native fail
  with the reason. The script gets `None` and the failure is counted, as for any native.

## The pairs

| Native | Condition function (stored index) | Parameters |
| --- | --- | --- |
| `Actor.IsFlying` | `GetIsFlying` (594) | none |
| `Actor.IsOnMount` | `IsRidingMount` (327) | none |
| `Actor.IsBeingRidden` | `IsBeingRidden` (714) | none |
| `Actor.GetSitState` | `GetSitting` (159) | none |
| `Actor.GetSleepState` | `GetSleeping` (49) | none |
| `Actor.GetGoldAmount` | `GetGold` (48) | none |
| `Actor.IsSneaking` | `IsSneaking` (286) | none |
| `Actor.IsTrespassing` | `IsTrespassing` (145) | none |
| `Actor.WornHasKeyword` | `WornHasKeyword` (682) | keyword |
| `Actor.HasFamilyRelationship` | `HasFamilyRelationship` (259) | other actor |
| `Actor.HasParentRelationship` | `HasParentRelationship` (261) | other actor |
| `Actor.HasAssociation` | `HasAssociationType` (258) | other actor, association type |
| `ObjectReference.HasEffectKeyword` | `HasMagicEffectKeyword` (699) | keyword |
| `ObjectReference.IsInDialogueWithPlayer` | `IsInDialogueWithPlayer` (249) | none |
| `ObjectReference.HasRefType` | `HasRefType` (561) | location ref type |
| `ActorBase.GetDeadCount` | `GetDeadCount` (84) | the actor base |
| `Location.GetRefTypeAliveCount` | `GetRefTypeAliveCount` (592) | the location, ref type |
| `Location.IsLoaded` | `IsLocationLoaded` (625) | the location |
| `Scene.IsActionComplete` | `IsSceneActionComplete` (550) | the scene, action index |

`HasAssociation(akAssociation, akOther)` takes its arguments in the other order from the
condition, which takes the actor first. `GetSitState` and `GetSleepState` use the codes of
their conditions: 0 not, 2 wants to, 3 is, 4 wants to stop (Creation Kit wiki). The wiki
notes that `GetSleeping` also reads 1 while the bed idle loads; OpenSky never reports 1.

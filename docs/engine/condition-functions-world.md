---
type: Subsystem
title: Condition functions on world state
description: The condition functions that read fights, references, packages, crime,
  relationships, equipment, motion, spells, and locations, and where OpenSky's answer
  differs from the game.
tags: [engine, conditions, runtime]
---

# Condition functions on world state

This page continues [condition functions](/engine/condition-functions.md). The same rules
hold: "stored" is the index in the plugin, and the Creation Kit number is 4096 higher. A
function whose snapshot is missing fails with a reason; it never guesses. Indices and
parameter types come from xEdit `wbDefinitionsTES5.pas`. The meaning of each function comes
from its Creation Kit wiki page under <https://ck.uesp.net/wiki/>.

Where OpenSky lacks the system a function asks about, the function answers what the engine
does model. Each such answer is listed below.

## Combat actions

`GetWantBlocking` (0), `IsWeaponMagicOut` (101), `IsFleeing` (329), `IsBlocking` (569),
`GetAttackState` (574), `IsAttacking` (672), `IsPowerAttacking` (673), `IsStaggered` (701),
`IsRecoiling` (702), and `GetKnockedStateEnum` (725) read what the actor's body does in a
fight. The combat loop fills this for NPCs, and the melee state for the player.

- `GetAttackState` codes follow the game's attack-state enumeration as CommonLibSSE names it
  (`ATTACK_STATE_ENUM`). OpenSky reaches only the melee codes.
- OpenSky has no power attacks, no recoil, and no knock-down while alive. So
  `IsPowerAttacking` and `IsRecoiling` are 0, and `GetKnockedStateEnum` is 0, the standing
  state.
- `IsWeaponMagicOut` is 1 when a weapon or a spell is drawn.

## Reference state

`GetLocked` (5), `GetOpenState` (157), `GetInContainer` (624), `IsUnlockedDoor` (718), and
`DoesNotExist` (726) read the plugin placement plus runtime changes.

- `GetOpenState` answers 1 open or 3 closed. OpenSky has no opening or closing phase, so 2
  and 4 never occur. The `GetOpenState` native answers the same.
- `GetInContainer` is always 0. An item inside a container is a count, not a placed
  reference.
- `GetIsObjectType` (432) takes xEdit's `wbFormTypeEnum` (0 `ACTI`, 3 `CONT`, 4 `DOOR`,
  13 `NPC_`, 22 `FURN`, and more) and tests the record type of the base form. A base type
  that the record index does not hold, such as `STAT`, fails as unavailable.
- `IsCarryable` (487) is 1 when the base is an item record: `WEAP`, `ARMO`, `BOOK`, `INGR`,
  `MISC`, `ALCH`, `KEYM`, `AMMO`, `SLGM`, `SCRL`, or `APPA`. A light can be carried only when
  its `DATA` flag says so. The record index does not hold that flag, so a `LIGH` base fails
  as unavailable.

## Packages

`GetIsCurrentPackage` (161), `GetWithinPackageLocation` (325), `IsNullPackageData` (611), and
`GetNumericPackageData` (612) read the package the actor runs now. Package data is indexed by
its `UNAM` index. An actor that runs no package has no data, so each data function reads 0.

- `GetSleeping` (49) is 3, "is sleeping", while the sleep procedure runs, and 0 otherwise.
  OpenSky has no lie-down or wake-up phase, so 1, 2, and 4 never occur.
- `GetOffersServicesNow` (255) reads the `PKDT` general flag 0x01, "Offers Services"
  (UESP "Skyrim Mod:Mod File Format/PACK").
- `GetAllowWorldInteractions` (503) reads the `PKDT` interrupt flag bit 9, "World
  Interactions" (xEdit `wbPKDTInterruptFlags`).

## Script-set actor state

These read what a native or the dialogue stored in the actor's
[script state](/engine/papyrus-script-state.md):

- `GetEquippedShout` (579) compares the shout `EquipShout` stored.
- `IsInFavorState` (635) reads `SetDoingFavor`.
- `GetTalkedToPC` (50) is set when the actor says any line to the player, a greeting
  included.
- `HasBeenEaten` (127) is set on the corpse by the feeding natives.
- `GetVampireFeed` (226), `GetCannibal` (227), and `GetCurrentShoutVariation` (676) are 0.
  Feeding plays no animation, so no actor is in the middle of it, and OpenSky shouts no
  variations.
- `IsUndead` (715) is 1 when the actor's race carries the keyword `ActorTypeUndead`.

## Mounts and flight

- `IsRidingMount` (327) is 1 for a rider on a saddle bone. A passenger on a cart rides no
  mount. `IsBeingRidden` (714) is 1 for the mount under such a rider.
- `IsPlayersLastRiddenMount` (339) is the horse the player sat on last, kept after they get
  off.
- `GetFlyingState` (633) is 0, `FLY_STATE_NONE`. `CanFlyHere` (731), the land requests
  (646, 647), and the flying-mount functions (730, 732, 733) are 0. No actor flies yet.

## Crime

- `GetAlarmed` (61), `IsTrespassing` (145), `IsActorAVictim` (314), and `GetArrestingActor`
  (657) read the crime state of the current frame.
- `GetArrestedState` (656) is 1 for the player while a guard confronts them.
- `GetTrespassWarningLevel` (144) counts the warnings the guard gave under its Guard
  package ([package schedules](/engine/package-schedules.md#guard)).
- `IsGuard` (125) and `CanPayCrimeGold` (497) use the same guard faction rule as the arrest
  dialogue ([crime](/engine/crime.md)).
- `GetDaysInJail` (499) is the length of the last sentence served.
- `IsOwner` (278) compares the run-on with the owner of the parameter reference.

## Relationships

- `GetShouldAttack` (66) and `ShouldAttackKill` (678) use the hostility rule of the combat
  loop. OpenSky does not split "attack" from "attack to kill".
- `IsInFriendStateWithPlayer` (638) is 1 when the relationship rank toward the player is
  at least 1 (Friend).
- `HasAssociationType` (258) takes an `ASTP` in parameter 2. `HasFamilyRelationship` (259)
  is true for any family association. `HasParentRelationship` (261) needs the association
  with the editor ID `ParentChild`, with the parameter as the parent.
- `GetLowestRelationshipRank` (616) is the lowest rank in any `RELA` that names the actor,
  and 0 with none.
- `GetPCInFaction` (132) and `GetInSharedCrimeFaction` (652) read faction membership.

## Equipment

- `GetEquippedItemType` (597) uses the casting-source codes of the Creation Kit page: 0
  nothing, 1 to 8 the weapon types, 9 spell, 10 shield, 11 torch, 12 crossbow.
- `GetReplacedItemType` (664) and `HasBoundWeaponEquipped` (706) are 0. OpenSky keeps no
  replaced item and has no bound weapons yet.
- `GetWeaponAnimType` (108) and `IsWeaponSkillType` (109) read the right-hand weapon's
  `DNAM`.
- `GetClothingValue` (41) adds the value of every worn apparel item.
- `WornHasKeyword` (682) and `WornApparelHasKeywordCount` (722) test worn items only.
- `GetKeywordItemCount` (465) counts every held item with the keyword.

## Motion

`GetPos` (6), `GetVelocity` (446), and the path functions take an axis. `ptAxis` stores the
letter: 88 X, 89 Y, 90 Z.

- Angles are degrees in -180 to 180, rounded to a thousandth. A heading of 0 faces north
  (+Y) and grows clockwise, as a placement's Z rotation does.
- `GetMovementDirection` (589) answers 0 standing, 1 forward, 2 right, 3 back, 4 left. A
  body slower than 1 unit per second stands.
- `GetPathingTargetAngleOffset` (620) and the current-speed angle read the next waypoint.
  The turn speed about Z is 0 once the actor faces its waypoint. X and Y are always 0.
- `GetWithinDistance` (639) takes the distance as a float in parameter 2.
- `GetRelativeAngle` (584) about Z is the heading angle. About X it is the pitch up to the
  other reference.
- `GetTargetHeight` (720) and `GetActivatorHeight` (680) are how far the other reference
  stands above the run-on.

## Spells

- `SpellHasKeyword` (596) reads the spell in a casting source. A spell has a keyword when
  any of its effects has it.
- `EPMagic_SpellHasKeyword` (693), `EPMagic_SpellHasSkill` (696), and `SpellHasCastingPerk`
  (713) read the spell a perk entry point is evaluated for, such as `Mod Spell Cost`. The
  spell's school is the magic skill of its costliest effect.
- `GetDisease` (39) is 1 when the actor knows a spell of type disease.
- `IsDualCasting` (627) is 1 while the actor runs a dual cast. The Creation Kit page adds that
  damage taken mid-cast makes it 0 until the next dual cast; OpenSky does not do that yet.
- `EffectWasDualCast` (724) is 1 for an effect a dual cast applied. It is answered at apply time
  and in the per-second check of the effect's entry conditions.
- `IsWardState` (602) is true only for state 0, "none", because OpenSky has no wards.
- `EPAlchemyGetMakingPoison` (500), `IsPoison` (721), and `EPAlchemyEffectHasKeyword` (501)
  read the brew in progress while Mod Alchemy Effectiveness runs ([alchemy](/engine/alchemy.md)).
  Outside a brew they fail as unavailable.

## Locations

- `GetDeadCount` (84) counts the dead references of one base form.
- `IsPlayerInRegion` (117) reads the regions of the cell the player stands in.
- `GetMapMarkerVisible` (491) is 1 when the marker reference is visible on the map.
- `IsLocationLoaded` (625) is 1 when the player stands inside the location or one of its
  children. Only the player's area is loaded in OpenSky.
- `LocationHasRefType` (563), `GetRefTypeAliveCount` (592), and
  `GetLocAliasRefTypeAliveCount` (601) read the location's `LCSR` references of a type.
  A reference counts as alive until its actor dies.

## Recorded events

Some functions ask about something that happened earlier. The engine records it on the form
when it happens, in the [script state](/engine/papyrus-script-state.md), and the function
reads it back.

- `IsKiller` (408) is 1 when the run-on killed the parameter actor. The ragdoll step records
  the killer when an actor dies.
- `GetFriendHit` (288) counts the player's blows on the run-on while it was not hostile.
  OpenSky never resets the count; the game's reset rule is not documented.
- `IsLastHostileActor` (674) is 1 when the run-on is the last actor that hit the player.
- `GetDestroyed` (203) and `GetDestructionStage` (470) read the state the destruction
  natives keep ([Papyrus destruction](/engine/papyrus-destruction.md)). An object no script
  damaged reads 0.

## Actor situation

- `IsOverEncumbered` (734) uses the fast-travel weight rule for the player. NPCs carry no
  weight limit in OpenSky, so they read 0.
- `GetGroupMemberCount` (415) counts the actors in the run-on's fight. OpenSky has no combat
  groups, so every NPC in combat counts as one group: the count of NPCs that fight now. The
  player counts as a group of 1, and an actor out of combat reads 0.
- OpenSky models no injury, attack types, item-use reactions, player actions, or bump
  reactions. So `GetIsInjured` (645), `IsAttackType` (697), `GetIsUsedItemType` (247),
  `GetPlayerAction` (305), `IsSmallBump` (274), and `GetLastBumpDirection` (642) read 0.
- `GetBribeSuccess` (654) and `GetIntimidateSuccess` (655) follow the
  [speech checks](/engine/speech-checks.md).

## Dialogue lines

`IsTalking` (141), `IsGreetingPlayer` (123), `GetDialogueEmotion` (434), and
`GetDialogueEmotionValue` (435) read the line the dialogue speaker says now. The coordinator
sets the line when the speaker greets the player or answers a topic, and clears it when the
response ends. An actor that is not the speaker reads 0. The emotion codes are the `TRDT`
emotion type (0 Neutral to 7 Puzzled, xEdit `wbEmotionTypeEnum`) and the emotion value.
OpenSky has no NPC-to-NPC talk, so only the player's partner can talk.

## Interface and player

- `MenuMode` (36) with parameter 0 is 1 while any menu is open. xEdit does not list the
  codes for single menu types, so any other parameter fails as unresolved.
- `IsPlayerMovingIntoNewSpace` (358) is 1 only while a loading screen shows, as the Creation
  Kit wiki page says.

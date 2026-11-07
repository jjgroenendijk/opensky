---
type: Subsystem
title: Actor state graph variables
description: The actor-state variables the engine writes into the player's behavior graphs each
  step, the outputs it reads back, how iState is encoded, and the variables left unwritten.
tags: [engine, animation, behavior, player]
---

# Actor state graph variables

The behavior graphs share more than movement with the engine. The engine tells them what the actor
does: an attack, a guard, a cast, where the camera looks. The graphs report back what the animation
allows: whether the actor may turn, equip, or is in a recoil. The movement variables are on the
[locomotion graph](/engine/locomotion-graph.md) page.

Every name and direction comes from the install's character graphs, read with the census of
[HKX behavior graph objects](/formats/hkx-behavior.md). The Creation Kit list of animation variables
(<https://ck.uesp.net/wiki/List_of_Animation_Variables>) names many of them but gives no types.

## Inputs the engine writes

The locomotion bridge writes these each step, to both the third-person and the first-person graph.

| Variable | Type | Written as | Bound in the graph to |
| --- | --- | --- | --- |
| `bHeadTracking` | bool | The Head tracking setting | `BSLookAtModifier.lookAtTarget` |
| `TargetLocation` | quad | A point 1024 units along the camera view, world space | `BSLookAtModifier.targetLocation` |
| `camerafromx`, `camerafromy`, `camerafromz` | real | The camera position | Look and aim modifiers |
| `Pitch` | real | Camera pitch in radians, positive up | `hkbTwistModifier` in the bow aim |
| `bSprintOK` | bool | False when the stamina gate refuses a sprint | Sprint transition conditions |
| `iWantBlock` | int32 | 1 while the block key is held | Block and bow zoom conditions |
| `bWantCastLeft`, `bWantCastRight` | bool | True while that hand casts | `BSEventOnFalseToTrueModifier` |
| `bWantCastVoice` | bool | True while the player inhales a shout ([shouts](/engine/shouts.md)) | `BSEventOnFalseToTrueModifier` raising `BeginCastVoice` |
| `IsInCastState` | real | 1 while either hand casts, else 0 | Cast blends |
| `iRightHandEquipped`, `iLeftHandEquipped` | int32 | The hand's `iRightHandType` value while drawn, else 0 | Jump, sprint, stagger, and shout selectors |
| `IsBeastRace` | bool | The race has the `IsBeastRace` keyword | The unarmed attack selector |
| `iGetUpType` | int32 | 2 while swimming, else 1 | The get-up pose matcher |
| `weapAdj` | real | The player's weight / 100 | The expression that weights the [body-weight layer](/engine/behavior-clips.md#body-weight-layer) |
| `attackPowerStartTime`, `attackIntroLength`, `attackComboStartFraction` | real | 0.3666667, 0, and 0.5 ([attack timing](#attack-timing)) | Attack blends |
| `iState` | int32 | The value of one `iState_*` constant | State conditions |

The hand selectors list their children in the `iRightHandType` order: 0 unarmed, 1 to 4 one-handed,
5 two-handed sword, 6 two-handed axe, 7 bow, 8 staff, 12 crossbow. A sheathed weapon picks the
unarmed child, so OpenSky writes 0 then. The `IsBeastRace` keyword is the default object `KWBR`
(<https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/DOBJ>). The pose matcher under
`iGetUpType` has three children: 0 reanimate, 1 get up, 2 swimming.

In the reference game, a living bandit reads `iGetUpType` 0 until something knocks it down.
It reads 1 from the frame `pushactoraway` starts the ragdoll (observed 2026-11-04). So 0 is the
graph's start value, and the game writes the value when a get-up starts. OpenSky writes 1 or 2
each step instead, which picks the same child.

[WARNING] A reanimated corpse was not observed: a reanimate spell cast from the console did not
raise the corpse. OpenSky raises a reanimated corpse without a get-up, so no graph reads
`iGetUpType` 0 there yet.

[WARNING] The sign of `Pitch` on the spine twist is not yet checked against the game. The look
distance of `TargetLocation` is OpenSky's own.

## Attack timing

The game gives the player's graphs three fixed values. They do not change with the attack or
with how long the attack key is held. Read from the reference game through the bridge
([reference game](/tools/reference-game.md#recording-graph-variables)), observed 2026-11-04:

| Variable | The player | A bandit NPC |
| --- | --- | --- |
| `attackPowerStartTime` | 0.366667 | 0 |
| `attackIntroLength` | 0 | 0 |
| `attackComboStartFraction` | 0.5 | 0 |

The NPC values stay 0 through its normal attacks, power attacks, and weapon draws. Both actors
use the same graph files, so the player's values come from the game, not from the graph.
OpenSky writes the player's values each step and leaves NPC graphs alone. In `0_master.hkx` the clip
`DW1HM1HM_PowerAttackStab` takes `attackPowerStartTime` as its `startTime`, so the player's
dual-wield power stab starts 0.37 seconds into the clip (`openskycli hkx <graph> --bindings
attack` lists the bindings).

[WARNING] The player was read only at rest. Keys sent to the game under Wine do not reach the
player, so no player attack was recorded.

## How `iState` is encoded

`0_master.hkx` declares one int32 variable per actor state, such as `iState_NPC1HM` and
`iState_NPCSprinting`. Each holds the number that `iState` takes for that state. The engine reads the
numbers from the graph instead of hard-coding them, so a graph with other numbers still works. When
the graph declares no constant for the state, `iState` is not written.

The state is picked in a fixed order. The first match wins:

1. An attack: a power attack, a two-handed attack, or a plain attack.
2. A guard (`iState_NPCBlocking`), or `iState_NPCBlockingShieldCharge` while the graph tags it.
3. A fully drawn bow (`iState_NPCBowDrawn`), or `iState_NPCBowDrawnQuickShot` while the graph
   tags it.
4. A cast in either hand (`iState_NPCMagicCasting`).
5. Riding: `iState_HorseSprint` while the mount sprints, else `iState_NPCHorse`. `bIsRiding` is
   true while the player sits on a mount ([riding](/engine/riding.md)).
6. Drunk (`iState_NPCDrunk`), while the graph tags it (see below).
7. A sprint or sneak gait.
8. A drawn weapon, by the right-hand type: one-handed, two-handed, bow or crossbow, or staff or
   spell. The type uses the `iRightHandType` encoding ([combat graph names](/engine/combat-graph-names.md)).
9. Otherwise `iState_NPCDefault`.

[INFO] This order is OpenSky's own. No source states the game's order. Bleedout has no
OpenSky system yet, so no step picks it.

## Perk states

Two states are reached only inside the graph, from a perk's graph flag. The perk entry point
Set Boolean Graph Variable sets the flag, and the combat runtime writes it while the perk applies.
The names mislead: neither flag comes from the perk it is named after.

| Flag | Set by the perk | Graph state | Tag |
| --- | --- | --- | --- |
| `bPerkQuickShot` | Ranger (`058F63`) | `BowAttackPerkQuickShot` | `iState_NPCBowDrawnQuickShot` |
| `bPerkShieldCharge` | Block Runner (`106253`) | `BlockShieldChargeState` | `iState_NPCBlockingShieldCharge` |

The Quick Shot perk (`105F19`) sets `bPerkQuickdraw`, which no graph of the install declares. Its
faster draw comes from its ability `PerkAbQuickShot`. `1hm_behavior.hkx` picks the start state of
`Bow_AttackRootBehavior` and `BlockBehavior` by the flag, so `bowAttackStart` or `blockStart` enters
the perk state directly. A sprint does not change the guard state. Each perk state runs a
`BSiStateTaggingGenerator` that tags its constant (16 and 17 in `0_master.hkx`), and OpenSky reports
that tag through `iState`, as it does for drunk. This shows it:

```sh
openskycli hkx meshes\actors\character\behaviors\0_master.hkx --set iLeftHandType=10 \
  --set iRightHandType=1 --set bPerkShieldCharge=1 --raise weapEquip --raise blockStart
```

The Shield Charge perk (`058F6A`) itself is no graph state. It gives the ability
`shieldChargeSpell`: a cloak of 6 feet and a 10 point Damage Stamina, both only while the player
sprints, blocks, and does not ride (`IsSprinting`, `IsBlocking`, `IsRidingMount`). See [magic
archetypes](/engine/magic-archetypes.md#cloak-knock) for the knock it gives.

`openskycli game debug perk <editorID> [on|off]` gives or takes a perk. `state player` gives
`perks`, `cloak`, and `graph.perkState`. The Player & Locomotion panel shows `iState` by its
constant's name.

## Drunk actors

An actor is drunk while its graph is in the `MT_Drunk` state of `mt_behavior.hkx`. Two idle
records in `Skyrim.esm` move it there and back. Both name `Actors\Character\Behaviors\0_Master.hkx`,
with no conditions and no parent:

| Idle | Form ID | Event |
| --- | --- | --- |
| `IdleDrunkStart` | `0CEFD0` | `DrunkStart` |
| `IdleDrunkStop` | `0CEFD1` | `DrunkStop` |

`0_master.hkx` passes the event to `mt_behavior.hkx`. There the state machine
`DefaultOrDrunkBehavior` goes from `NonDrunkState` to `MT_Drunk` on `DrunkStart`, and back on
`DrunkStop`. Inside `MT_Drunk`, `DrunkStanding` plays `IdleDrunk.hkx` and its two turn clips, and
`moveStart` leads to `DrunkLocomotion`, which plays `IdleDrunk_Walk.hkx`. The machine's sync
variable is `iDrunkVariable`.

`MT_Drunk` runs the `BSiStateTaggingGenerator` `MT_Drunk_iStateGen`. While it runs, the graph
tags the value 15, which is the value of `iState_NPCDrunk` in `0_master.hkx`. The graph files
hold many such generators, for example `Sprint_iStateGen` and `BleedOut_iStateGen`. OpenSky
reads the tag with the highest `m_iPriority`; on a tie the first one reached wins. No source
states the game's tie rule.

OpenSky treats an actor as drunk while its graph's tag equals `iState_NPCDrunk`:

- The player's `iState` takes `iState_NPCDrunk` (step 6 above).
- An NPC's `iState` takes the winning tag's value after each step, and the value the graph
  started with when nothing tags: 0 (`iState_NPCDefault`) for a human, 60 (`iState_HorseDefault`)
  for a horse.

## How the game picks `iState`

A clean-room read of `SkyrimSE.exe`, 2026-11-07, found the rule for every actor, the player
included: each running tagging generator pushes its value with its priority, and the highest
priority wins. With no tag, `iState` keeps the graph's starting value. The graph's speed sampler
reads `iState` as its table ([speed data](/formats/speed-data.md)), and the movement type whose name
matches the `iState_*` constant sets the actor's speeds. OpenSky does this for an NPC's walk and
run. The tags, read from the install's behaviour files:

| Tag | Value | Priority |
| --- | --- | --- |
| `MT_Drunk_iStateGen` | 15 (`NPCDrunk`) | 1 |
| `1HM_iStateGen` | 6 (`NPC1HM`) | 2 |
| `2HM_iStateGen`, `2HW_iStateGen` | 7 (`NPC2HM`) | 3 |
| `Bow_iStateGen`, `CrossBow_iStateGen` | 8 (`NPCBow`) | 4 |
| `Magic_iStateGen`, `MagicReady_iStateGen` | 9 (`NPCMagic`) | 5 |
| `Sprint_iStateGen` | 1 (`NPCSprinting`) | 7 |
| A normal attack | 12 (`NPCAttacking`) | 8 |
| A two-handed attack | 13 (`NPCAttacking2H`) | 9 |
| An NPC power attack | 14 (`NPCPowerAttacking`) | 10 |
| `MagicCasting_iStateGen` | 10 (`NPCMagicCasting`) | 11 |
| `Sneak_iStateGen`, `MT_Sneak_iStateGen` | 2 (`NPCSneaking`) | 12 |
| A bow or crossbow attack or reload | 3 (`NPCBowDrawn`) | 13 |
| A quick shot | 16 (`NPCBowDrawnQuickShot`) | 14 |
| `BlockDefault_iStateGen`, `MagicBlock_iStateGen` | 4 (`NPCBlocking`) | 15 |
| A shield charge | 17 (`NPCBlockingShieldCharge`) | 16 |
| `BleedOut_iStateGen` | 5 (`NPCBleedout`) | 17 |
| `sneakBowQuickShot_iStateGen` | 2 (`NPCSneaking`) | 22 |

The player's power attacks tag 12, not 14. The horse graph starts at 60 and tags 61
(`HorseSprint`), 62 (`HorseFall`), and 63 (`HorseSwim`). No tag sets 11 (`NPCHorse`); what sets
it is not known.

[WARNING] The player's `iState` still follows OpenSky's own order above, not the tags.

After `DrunkStop` the actor stays drunk until the blend out of `MT_Drunk` ends, because the
tagging generator runs as long as the old state is blended in.

`openskycli hkx meshes\actors\character\behaviors\0_master.hkx --raise DrunkStart --raise moveStart`
shows the states and the tag. `openskycli game debug drunk <ref> on|off` raises the event on a
running actor, and `state player` and `state actors` give `drunk` and `iState`.

In the vanilla data nothing plays the two idles. No `PACK`, `SCEN`, `QUST`, or `NPC_` record names
them, and no script in `Skyrim - Misc.bsa` sends `DrunkStart`. Tavern drunks such as the ones of
`FavorJobsDrunksFaction` walk normally in the game as well. A mod reaches the state with
`PlayIdle(IdleDrunkStart)` (<https://ck.uesp.net/wiki/PlayIdle_-_Actor>) or
`Debug.SendAnimationEvent(akActor, "DrunkStart")`
(<https://ck.uesp.net/wiki/SendAnimationEvent_-_Debug>). The animation variable list names
`iState_NPCDrunk` "Sets actor in a drunk state" (<https://ck.uesp.net/wiki/List_of_Animation_Variables>).

[WARNING] Whether the game keeps the drunk state in a save, or after the actor's graph reloads,
is not known. OpenSky loses it when the graph stops.

## How `iCombatStance` is encoded

Only the horse graphs read `iCombatStance`. It picks the start state of `StandingIdleBehavior`:
0 starts `NonCombat`, 1 starts `Combat`. The transitions between them fire on `combatStanceStart`
and `combatStanceStop`. The engine writes 1 while the rider's (or the horse's own) weapon is drawn,
and raises the event on the edge. Every actor graph gets the same write, so an NPC horse follows
its rider too.

## Outputs the graph publishes

The graph writes these through `BSIsActiveModifier`, a state machine's `isActive` or
`currentStateId`, a sync variable ([behavior state machines](/engine/behavior-state-machines.md)),
or an expression assignment. Examples: `bAnimationDriven`, `bAllowRotation`, `bEquipOK`,
`IsRecoiling`, `bIsSynced`, `iSyncIdleLocomotion`. No engine system acts on them yet.

## Variables left unwritten

Many names on the Creation Kit list are tuning values. The graph file gives them a non-zero
start value, such as `fMinSpeed`, `TurnMin`, `RotMax`, `SpeedAcc`, `PitchAcc`, `PitchThresh`,
`iCharacterSelector`, and `iSyncTurnDirection`. No script reads them, so OpenSky keeps the
graph's own value ([gap report](/tools/gaps.md)).

The game leaves two names from the list at the graph's value, so OpenSky does too. The gap
report counts them as "left at the graph's value by the game". Observed 2026-11-04:

- `weapChangeStartFraction` reads 0 on the player at rest, and stays 0 on a bandit while it
  draws its weapon.
- `IsInCastStateDamped` stays 0 on a mage bandit through a whole cast, while `IsCastingLeft`
  is 1 and `iState` is `iState_NPCMagicCasting`. `IsInCastState` stays 0 too.

[WARNING] No player cast was observed. OpenSky writes `IsInCastState` 1 while the player casts,
and no source confirms that the game does.

These still need a value from the engine, and no OpenSky system can give it yet:

- `PitchOffset`, `TweenPosition`, and `TweenRotation`: dragon flight.

Perk flags such as `bPerkQuickShot` come from the perk entry point Set Boolean Graph Variable
([perk states](#perk-states)).

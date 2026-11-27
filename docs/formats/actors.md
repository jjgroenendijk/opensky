---
type: File Format
title: Actor records (ACHR, NPC_, LVLN/LVLI, RACE, CLAS)
description: Layouts of the actor records, the template flags, and the FaceGen asset paths.
tags: [format, plugin, actors, achr, npc, leveled, template, race, class, facegen]
---

# Actor records

These records place an actor, say what it looks like, and give its stats and AI settings.
[Actor resolution](/engine/actor-resolution.md) explains how OpenSky combines them into a
rendered actor. [Actor values](/engine/actor-values.md) explains how the stat fields become
health, magicka, and stamina. Armor, armature, and outfit records are on
[armor records](/formats/armor.md).

Sources:

- UESP "Skyrim Mod:Mod File Format" pages `/ACHR`, `/NPC_`, `/LVLN`, `/LVLI`, `/RACE`,
  and `/CLAS` (<https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format>).
- xEdit dev-4.1.6 `wbDefinitionsTES5.pas` (template flag masks, `wbAIDT`) and
  `wbDefinitionsCommon.pas` (`wbLeveledListEntry`).
- Creation Kit wiki: "Template Data", "AI Data Tab"
  (<https://ck.uesp.net/wiki/AI_Data_Tab>), and "Race".

All integers and floats are little-endian.

## ACHR

A placed NPC. It has the same shape as REFR and lives in the same CELL child groups. An
ACHR that is persistent in a worldspace is stored under the worldspace persistent cell
([ESM groups](/formats/esm.md#worldspace-persistent-cell)).

| field | type | meaning |
| --- | --- | --- |
| `NAME` | FormID | base `NPC_`; required |
| `DATA` | float32[6] | position, then rotation in radians; required |
| `XSCL` | float32 | scale; absent means 1.0 |
| `VMAD` | struct | scripts; see [VMAD](/formats/vmad.md) |

Record-header flag `0x800` means "initially disabled": a script must enable the actor
before it appears. Header flag `0x200` means "starts dead". The other fields, such as `XEZN`,
patrol data, `XRGD`/`XRGB`, `XLCM`, `XESP`, `XOWN`, `XLCN`/`XLRL`, and `XLKR` (4 or 8 bytes),
are read as on a REFR ([placed references](/formats/placed-references.md#other-refr-and-achr-fields)).

## NPC_

| field | type | meaning |
| --- | --- | --- |
| `EDID` | zstring | editor ID |
| `FULL` | lstring | name |
| `ACBS` | 24 bytes | flags, template flags, and stats; required |
| `CNAM` | FormID | class (`CLAS`) |
| `DNAM` | 52 bytes | skills and the editor's calculated health, magicka, and stamina |
| `TPLT` | FormID | template, an `NPC_` or an `LVLN` |
| `RNAM` | FormID | race; required |
| `VTCK` | FormID | voice type (`VTYP`) |
| `WNAM` | FormID | skin `ARMO`; absent means the race skin |
| `PNAM` | FormID | head part (`HDPT`); repeated |
| `DOFT` | FormID | default outfit (`OTFT`) |
| `PKID` | FormID | AI package; repeated, in order |
| `SNAM` | struct | faction membership; see [factions](/formats/factions.md) |
| `CRIF` | FormID | crime faction, the faction the actor reports crimes to |
| `AIDT` | 20 bytes | AI data |
| `VMAD` | struct | scripts |

`ACBS`:

| offset | type | meaning |
| --- | --- | --- |
| `0x00` | uint32 | flags: `0x01` female, `0x08` respawn, `0x10` auto-calc stats, `0x20` unique, `0x80` PC level multiplier; more below |
| `0x04` | int16 | magicka offset |
| `0x06` | int16 | stamina offset |
| `0x08` | uint16 | level, or level multiplier x1000 when the PC flag is set |
| `0x0A` | uint16 | auto-calc minimum level |
| `0x0C` | uint16 | auto-calc maximum level |
| `0x0E` | uint16 | speed multiplier (actor value 30) |
| `0x10` | uint16 | disposition base |
| `0x12` | uint16 | template flags |
| `0x14` | int16 | health offset |
| `0x16` | int16 | bleedout override, in health points |

`DNAM` holds 18 base skill bytes, 18 skill-modifier bytes, and three int16 values at
`0x24`, `0x26`, and `0x28`: health, magicka, and stamina. UESP calls them "calculated health
(if auto-calc stats is on, otherwise seems to be random)". So they are the editor's own
answer. OpenSky uses them only to check its derivation, never as input. They are signed: a
creature with a negative magicka offset stores a negative value here.

More `ACBS` flags and what the game does with them:

| Bit | Effect |
| --- | --- |
| `0x4` | Chargen face preset. The tint layers are kept at load only with this bit, or when `bUseFaceGenPreprocessedHeads:General` is off. Every `0x4` NPC of a race and sex, except the player's base, is one preset in the race menu |
| `0x100` | The NPC has its own creature sounds. Reading `CSDT` or `CSDI` sets it, and `CSCR` clears it. Set: the sounds come from `CSDT`, `CSDI`, and `CSDC`; clear: from the `CSCR` NPC, one level deep |
| `0x10000` | No blood on a hit: no screen blood when the player is hit, and no spatter or impact effect on the actor. `bDisableAllGore`, or the race flags `0x2000` and `0x4000` together, do the same |
| `0x40000` | The bleedout threshold is the `ACBS` bleedout override ([bleedout](/engine/ragdoll.md#bleedout)) |
| `0x80000` | The actor uses the behaviour graph of the opposite sex, and the graph gets the opposite sex value (1 female, 0 male) |
| `0x100000` | No facial animation: no expressions, blinking, or lip movement, and no expression change on a hit, at death, or from mood |

No reader of `0x4000`, `0x20000`, `0x200000`, `0x4000000`, or `0x10000000` exists.

Template flags say which field groups come from the `TPLT` record: `0x0001` traits,
`0x0002` stats, `0x0004` factions, `0x0008` spell list, `0x0010` AI data, `0x0020` AI
packages, `0x0040` model and animation, `0x0080` base data, `0x0100` inventory, `0x0200`
script, `0x0400` default package list, `0x0800` attack data, `0x1000` keywords. The game
never reads `0x0040`.
[Actor resolution](/engine/actor-resolution.md) lists which fields each flag covers.

`AIDT` uses Creation Kit names. UESP and xEdit agree on every offset.

| offset | type | meaning |
| --- | --- | --- |
| `0x00` | uint8 | aggression: 0 unaggressive, 1 aggressive, 2 very aggressive, 3 frenzied |
| `0x01` | uint8 | confidence: 0 cowardly to 4 foolhardy |
| `0x02` | uint8 | energy, how often the actor moves in a sandbox, 0 to 100 |
| `0x03` | uint8 | morality: 0 any crime to 3 no crime |
| `0x04` | uint8 | mood; the wiki calls it "Not used" |
| `0x05` | uint8 | assistance: 0 helps nobody, 1 helps allies, 2 helps friends and allies |
| `0x06` | uint8 | bit 0: uses aggro radius behavior |
| `0x07` | uint8 | xEdit "Unused"; UESP sees junk |
| `0x08` | uint32 | warn distance |
| `0x0C` | uint32 | warn-or-attack distance |
| `0x10` | uint32 | attack distance |

An `AIDT` shorter than 8 bytes gives no AI data. One that ends before `0x08` has no
distances. An actor without `AIDT` counts as unaggressive.

## LVLN and LVLI

Leveled NPC and leveled item lists share one layout. LVSP (leveled spell) uses it too; see
[shouts and equip slots](/formats/shouts-equip-slots.md).

| field | type | meaning |
| --- | --- | --- |
| `EDID` | zstring | editor ID |
| `LVLD` | uint8 | chance none; UESP says always 0 on LVLN |
| `LVLF` | uint8 | flags: `0x01` all levels, `0x02` each count, `0x04` use all, `0x08` special loot (UESP `LVLI`) |
| `LVLO` | struct | one entry; repeated |

With "use all" set, every entry applies together. For example, `ArmorStormcloakSet` gives
boots, cuirass, gauntlets, and a helmet list. Without it, the game picks one entry.

UESP gives `LVLO` as 12 bytes: uint32 level, FormID, uint32 count. xEdit's
`wbLeveledListEntry` reads uint16 level, 2 padding bytes, FormID, and also accepts an 8-byte
form where the count is 1. Both read the same bytes for normal values. OpenSky accepts both.
A `COED` owner subrecord may follow an `LVLO`. OpenSky also reads `OBND`, the `LLCT` entry
count (advisory; the decoded entries count), `MODL`, and `LVLG`, a `GLOB` that overrides the
chance none.

## RACE

| field | type | meaning |
| --- | --- | --- |
| `EDID` | zstring | editor ID |
| `FULL` | lstring | name |
| `WNAM` | FormID | default skin `ARMO` for an NPC_ without `WNAM` |
| `BOD2`/`BODT` | struct | body template; see [armor records](/formats/armor.md) |
| `DATA` | 128 or 164 bytes | form version 40 or 43 |
| `MNAM`/`FNAM` | 0 bytes | marker: the next block is male or female |
| `ANAM` | zstring | skeleton path for the current gender |
| `NAM0` | 0 bytes | opens the head-data blocks |
| `HEAD` | FormID | default head part (`HDPT`); repeated |

`DATA` (source: xEdit `dev-4.1.6`, commit `9fb0168`, `wbRecord(RACE, ...)`):

| offset | type | meaning |
| --- | --- | --- |
| `0x00` | 7 x (int8, int8) + uint16 | skill bonuses: actor value, then bonus |
| `0x10` | float32 x 4 | male and female height, then male and female weight |
| `0x20` | uint32 | flags: `0x1` playable, `0x2` FaceGen head; more under "RACE DATA in the game" |
| `0x24` | float32 x 3 | starting health, magicka, stamina |
| `0x30` | float32 x 4 | base carry weight, base mass, acceleration, deceleration |
| `0x40` | uint32 | size: 0 small, 1 medium, 2 large, 3 extra large |
| `0x44` | int32 x 2 | head and hair biped object; -1 is none |
| `0x4C` | float32 | injured health percent |
| `0x50` | int32 | shield biped object |
| `0x54` | float32 x 3 | health, magicka, stamina regen |
| `0x60` | float32 x 2 | unarmed damage and reach |
| `0x68` | int32 | body biped object |
| `0x6C` | float32 x 4 | aim angle tolerance, flight radius, angular acceleration, angular tolerance |
| `0x7C` | uint32 | flags 2, form version 43 only |
| `0x80` | float32 x 9 | mount, dismount, and mount camera offsets, form version 43 only |

A skill pair with a bonus of zero is an empty slot. `NordRace` gives Two-Handed +10 and
One-Handed, Block, Smithing, Light Armor, and Speech +5, which matches UESP. Every playable
vanilla race has 300 carry weight, mass 1, unarmed damage 4, starting values 50/50/50, and
regen 0.7/3/5 percent of the maximum per second. The Creation Kit says: "Health Regen: The
percentage of total Health that is regenerated each second".

### RACE DATA in the game

How the game uses the `DATA` values. Each length below is in game units and is multiplied by the
actor's scale.

- Unarmed reach: an actor with no weapon, or with the built-in fists, reaches this far. It is not
  multiplied by `fCombatDistance` and never combines with a weapon's reach. `NordRace` reaches 96
  units unarmed ([melee combat](/engine/melee-combat.md#reach-and-the-hit-volume)).
- Acceleration, deceleration, and angular acceleration: each is the time in seconds to reach run
  speed, to stop from it, or to reach the full turn rate
  ([movement types](/formats/movement-types.md#acceleration)). A larger value ramps more slowly.
  In combat pathing the rates are multiplied by `fCombatPathingAccelerationMult`,
  `fCombatPathingDecelerationMult`, or `fCombatPathingRotationAccelerationMult` (2 each), which
  halves each time. The combat turn speed is at least 2.25 on the normalized scale, which is
  1.25 times rotate in place run.
- Angular tolerance, in degrees: how close the actor must turn toward a point before it faces it.
  With a ranged weapon type, `fAIUseWeaponToleranceDegrees` replaces it.
- Aim angle tolerance, in degrees: the combat aim tolerance is the larger of this and
  `fCombatAngleTolerance` (1), turned into radians. An actor turning to aim at its combat target
  uses it with the angular acceleration above. When the aim asks for it, the behaviour graph
  float `AimHeadingMax`, in degrees, can raise the tolerance; it never lowers it.
- Flight radius: while the actor flies, its path requests use this radius times the actor's
  scale (reference scale times `NAM6` height). When it does not fly, or while it lands, the
  character controller's radius is used.
- Shield biped object: the worn armour in that slot is the actor's shield. Body biped object: the
  worn armour in that slot is the actor's body armour; -1 is none. Head and hair: the race
  menu rebuilds the head from them after a race change. The player's race head, hair, body, and
  shield slots are also kept with the player.
- The male and female weights, and the two bytes after the skill pairs, have no known reader.

More `DATA` flags:

| Bit | Effect | Vanilla races |
| --- | --- | --- |
| `0x8` | The movement controller tilts the body front and back to the ground | Four-legged animals |
| `0x10` | The movement controller tilts the body left and right to the ground | Mudcrab, spiders, mammoth |
| `0x20` | No live reader | Ice wraith, magic anomaly |
| `0x200` | The actor cannot move, and its AI does not move it. Setting its heading adds the X turn into Z | `dunMiddenEmptyRace` |
| `0x800` | In combat, a swimming race (`0x40`) with this bit swims only when its combat state allows it | |
| `0x8000` | Head tracking through the behaviour graph | |
| `0x10000` | Spell aim starts at the magic node | |
| `0x40000` | Another collision layer for the body | |
| `0x80000` | Health regenerates at the full rate in combat ([actor values](/engine/actor-values.md)) | Trolls, werewolf |
| `0x100000` | The actor's paths may open doors | |
| `0x200000` | The player may talk to the actor, unless overridden | |
| `0x800000` | Part of the pickpocket check | |
| `0x1000000` | Read when a non-player actor's character controller is built | Dragons |
| `0x4000000` | A race change rebuilds the head parts and adds the race's default head parts | |
| `0x8000000` | A race change rebuilds the head parts from the race | `WerewolfBeastRace` |
| `0x20000000` | Several membrane shaders may play on the actor at once | |
| `0x40000000` | The actor may hold an item in the left hand | |
| `0x80000000` | An actor query returns it; its caller is not known | Mammoth, giant |

The ground tilt of `0x8` and `0x10` takes the ground normal under the actor in the actor's
own frame. The roll target is `-normal.x` and the pitch target is `normal.y`, each used
directly as an angle in radians and clamped to plus or minus 0.820 (47 degrees). When the
actor is placed, the target applies at once. While it moves, the tilt moves 30% of the way to
the target at each update. Each ground sample restarts a 5-second timer; when it runs out,
the tilt is worked out again. Example: a normal with `x = -0.2` gives a roll of 0.2 radians
(11.5 degrees). Flags 2: `0x1` turns on velocity-obstacle avoidance, but only when
the INI setting `bUseVelocityObstacles:Pathfinding` is on. `0x2` changes how the actor reacts to
a hit from the player, and `0x8` and `0x10` are fallbacks of an actor ability check, which the
mount checks use; their exact effects are not known.

Skeleton blocks come in this order (seen on `NordRace`): `MNAM`, male `ANAM` + `MODT`,
`FNAM`, female `ANAM` + `MODT`. Later `MNAM`/`FNAM` markers open other blocks, but those
carry `MODL`, not `ANAM`. So each `ANAM` pairs with the marker just before it.

For head data, `NAM0` opens a block, `MNAM` or `FNAM` picks the gender, and each `HEAD`
names a default head part. An `HDPT` pairs each `NAM0` kind with the next `NAM1` path: 0 is
the race morph, 1 is the expression TRI, 2 is the chargen morph. The `HDPT` `EDID` is the
name of the baked `BSDynamicTriShape`. See [TRI](/formats/tri.md).

### RACE sections

The same signature means different things in different parts of a `RACE`. OpenSky walks
the fields in order and tracks the current section and sex:

| Opener | Section | Fields in it |
| --- | --- | --- |
| start | skeleton | `ANAM` + `MODT` per sex, `ATKD`/`ATKE` attacks |
| `NAM1` | body | `INDX` + `MODL`/`MODT` per body part, per sex |
| `NAM3` | behavior | `MODL`/`MODT` behavior graph per sex, then `NAME` biped names, `MTYP`/`SPED` movement types, `VTCK`, `DNAM`, `HCLF`, `TINL`, `PNAM`, `UNAM`, `ATKR`, `NAM4`, `NAM5`, `NAM7`, `ONAM`, `LNAM`, `NAME`, `QNAM`, `UNES`, `WKMV`, `RNMV`, `SWMV`, `FLMV`, `SNMV`, `SPMV` |
| `NAM0` | head | `HEAD` parts, `MPAI`/`MPAV` morph groups, `RPRM`/`RPRF` presets, `AHCM`/`AHCF` hair colors, `FTSM`/`FTSF` face textures, `DFTM`/`DFTF`, `TINI` tint masks with `TINT`, `TINP`, `TIND`, `TINC`/`TINV`/`TIRS` presets |

`MNAM` and `FNAM` switch the sex inside a section. An `MTYP` counts only with a `SPED` after it,
and that `SPED` replaces the `MOVT`'s speeds for the race
([movement types](/formats/movement-types.md)).

`TINL` is named "Total Number of Tints in List", and xEdit marks it "Needs Count Updated".
On the install it equals the mask count plus the preset count on only 9 of 66 races; on
the rest it is larger, for example 1139 on `NordRace` against 67 masks and 1065 presets.
OpenSky keeps it as a number and does not check it.

### NPC_ details

Fields beyond the ones above, read into the actor's details:

| Field | Type | Meaning |
| --- | --- | --- |
| `SHRT` | lstring | Short name |
| `KWDA` | FormID array | Keywords |
| `NAM6`, `NAM7` | float | Height and weight |
| `NAM8` | uint32 | Sound level |
| `QNAM` | 3 floats | Texture lighting color |
| `NAM9` | 19 floats | Face morph values |
| `NAMA` | 4 int32 | Face parts: nose, unknown, eyes, mouth |
| `TINI`, `TINC`, `TINV`, `TIAS` | struct | One tint layer: index, RGBA color, interpolation, preset (int16) |
| `CSDT`, `CSDI`, `CSDC` | struct | Sound type, then sound and chance pairs |
| `INAM`, `ANAM`, `ATKR`, `ZNAM`, `GNAM`, `HCLF` | FormID | Death item, far-away model, attack race, combat style, gift filter, hair color |
| `NAM4`, `NAM5`, `HNAM` | bytes | Skipped by the game at load |
| `FNAM` | uint16 | Read and thrown away |
| `SPOR`, `OCOR`, `GWOR`, `ECOR` | FormID | Spectator, observe dead, guard warn, and combat package lists |
| `DPLT`, `SOFT`, `CSCR`, `FTST` | FormID | Default package list, sleeping outfit, sound parent, head texture |

The actor also reads the destruction, attack, and inventory groups; see
[records](/formats/records.md).

How the game uses some of them:

- `NAM6` height 0 counts as 1. The height multiplies the reference scale.
- `NAM8` sound level, default 1. A value above 4 counts as 1. It is the noise of the actor's
  attacks when no weapon gives one: 0 loud (`iSoundLevelLoud`, 100), 1 normal
  (`iSoundLevelNormal`, 50), 2 silent (`iSoundLevelSilent`, 0; `Skyrim.esm` sets 10), 3 very
  loud (`iSoundLevelVeryLoud`, 200), 4 none (0). The noise also starts the
  `fActorAlertSoundTimer` timer.
- `ATKR` names an attack race. Its attacks merge with the NPC's own, matched by `ATKE` event
  name ([attack data](/engine/attack-data.md#which-list-an-actor-uses)).
- `ANAM` is a far-away model, an `ARMO`. `DNAM` byte 44 is its distance, a float clamped to
  65,535 and kept as a whole number. In a cell with the right flag, an actor further than this
  from the camera wears one `ANAM` item; a nearer actor has it taken off.
- `QNAM` texture lighting: each float times 255 is kept as a byte.
- `OBND` places a summon: its 2D radius is the room the summon needs
  ([Summon Creature](/engine/magic-archetypes.md)).

## CLAS

`DATA` is 36 bytes:

| offset | type | meaning |
| --- | --- | --- |
| `0x00` | uint32 | unknown, "possibly flags" |
| `0x04` | uint8 | trainer skill, as the actor value index minus 6 |
| `0x05` | uint8 | trainer level: the skill level the trainer teaches up to; 0 trains nothing |
| `0x06` | uint8 x 18 | skill weights, for actor values 6 to 23 |
| `0x18` | float32 | bleedout default |
| `0x1C` | uint32 | voice points |
| `0x20` | uint8 x 3 | health, magicka, stamina weights |
| `0x23` | uint8 | flags; UESP: "0x1 seems to indicate guard" |

## FaceGen paths

Each NPC's baked head has two files. The key is the NPC_ that supplies the traits:

```text
meshes\actors\character\facegendata\facegeom\<plugin>\<id8>.nif
textures\actors\character\facegendata\facetint\<plugin>\<id8>.dds
```

`<plugin>` is the lowercased file name of the defining plugin (`skyrim.esm`). `<id8>` is the
FormID as 8 hex digits with the load-order byte set to `00`. The files exist only when the
race has the FaceGen head flag `0x2`. Playable races set it; creature races (cow, dog, bear)
do not. An NPC without head parts (Nazeem has no `PNAM`) still has files.

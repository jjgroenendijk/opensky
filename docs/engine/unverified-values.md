---
type: Reference
title: Unverified values
description: Every value and rule OpenSky chose without a source, with the page that explains it,
  so each one can be checked against the game later.
tags: [engine, verification]
---

# Unverified values

Some numbers and rules have no open source: the game keeps them in its code, and no record,
setting, or wiki page gives them. OpenSky then picks a value. This page lists every such
choice in one place, so that each one can be checked later against the
[reference game](/tools/reference-game.md) or a new source.

Each row names the value, what OpenSky uses, and the page that explains it. The page holds
the detail and the sources it did find.

## How to use this page

- A change that adds a value without a source adds a row here, and marks the value on its own
  page as OpenSky's choice.
- A row whose value is then confirmed is removed. The source goes on the subsystem page.
- A value that differs from the game, once measured, also needs a `gap` issue (root
  `AGENTS.md`).

## Combat

| Value or rule | OpenSky's choice | Page |
| --- | --- | --- |
| Melee hit volume | Half height 0.25 x capsule height, radius 0.75 x capsule radius | [melee combat](/engine/melee-combat.md) |
| NPC combo chance | 0.3 per swing, at most 3 swings, no Offensive Mult term | [combat behaviour](/engine/combat-behavior.md) |
| NPC back-off time | At most 2 s | [combat behaviour](/engine/combat-behavior.md) |
| Combat setting formulas | Read from the setting names | [combat](/engine/combat.md) |
| Knockback and knockdown formulas | Read from the setting names | [impulses](/engine/impulses.md) |
| Kill camera timing | OpenSky's numbers | [kill camera](/engine/kill-cam.md) |
| Projectile settings | Formulas read from the setting names | [projectiles](/engine/projectiles.md) |
| Arrow gravity unit | Read as the record value with no scale | [projectiles format](/formats/projectiles.md) |
| Trap scales, speed, repeat interval | OpenSky's numbers | [traps](/engine/traps.md) |
| Combat style choice | Not confirmed against the game | [combat style](/formats/combat-style.md) |

## Magic

| Value or rule | OpenSky's choice | Page |
| --- | --- | --- |
| Cone spell world test | Looks 192 units ahead every 0.125 s and stops at the first surface seen | [spell delivery](/engine/spell-delivery.md) |
| Ward power cap | `strongest ward x (base + mult x Restoration)`, so 1.3 x the stronger ward | [magic archetypes](/engine/magic-archetypes.md) |
| Ward charge-up | A straight line over one second | [magic archetypes](/engine/magic-archetypes.md) |
| Ward order | A ward applies before absorption | [spell delivery](/engine/spell-delivery.md) |
| Ward charge rate and break stagger | OpenSky's numbers | [spell delivery](/engine/spell-delivery.md) |
| Area and range cost terms | Area: `1 + mult x area`; range: a multiplier on aimed and target spells | [spellcasting](/engine/spellcasting.md) |
| Dual cast window | OpenSky's window | [spellcasting](/engine/spellcasting.md) |
| Staffs | Right hand only; whether the staff graph raises the cast event is not confirmed | [spellcasting](/engine/spellcasting.md) |
| Rune range | Read as feet | [spell delivery](/engine/spell-delivery.md) |
| Light and other spell radii | OpenSky's radius | [magic archetypes](/engine/magic-archetypes.md) |
| Telekinesis hold distance and throw speed | OpenSky's numbers | [magic archetypes](/engine/magic-archetypes.md) |
| Paralysis ragdoll speed scale | OpenSky's scale | [magic archetypes](/engine/magic-archetypes.md) |
| Shout times | How `fShoutTime1` and `fShoutTime2` are used | [shouts](/engine/shouts.md) |
| Sun gaze cone | Within 5 degrees of the sun | [session natives](/engine/papyrus-session-natives.md) |

## Actors, AI, and detection

| Value or rule | OpenSky's choice | Page |
| --- | --- | --- |
| Detection constants | Twelve values, such as a 90-degree half view cone | [detection constants](/engine/detection-constants.md#openskys-own-constants) |
| Crouch visual factor and light level scale | 0.5; one luminance unit is level 100 | [detection](/engine/detection.md) |
| `GetLightLevel` scale | Light level times 100 | [actor natives](/engine/papyrus-actor-natives.md) |
| Head tracking | 384 units; angles in degrees; behind angle and neck share | [head tracking](/engine/head-tracking.md) |
| Face morph settings | Units read as seconds and emotion points; offsets as radians | [face morphs](/engine/face-morphs.md) |
| Navigation | 128-unit ledge rule; 512-unit gait rule | [navigation](/engine/navigation.md) |
| Package fallback on a blocked path | A guess at the game's rule | [package schedules](/engine/package-schedules.md) |
| Scene package wait | A scene does not wait forever on its package | [scenes](/engine/scenes.md) |
| Follower commands | 0.5 s wait; acts at 128 units | [follower commands](/engine/follower-commands.md) |
| Assault alarm member | The resident member nearest the player | [guard response](/engine/guard-response.md) |
| Default `NAM7` weight | 50 | [actor resolution](/engine/actor-resolution.md) |
| Combat weapon choice | Picked once, not scored again in a fight | [actor resolution](/engine/actor-resolution.md) |
| Idle naming and entry side rules | Read from names seen on the install | [idle runtime](/engine/idle-runtime.md) |
| Furniture rotation | Reset on standing up | [furniture](/engine/furniture.md) |
| Vehicle trailer and gait clips | An approximation of the game | [vehicles](/engine/vehicles.md) |
| Dragon animation | A guess; its graph does not run | [actor animation](/engine/actor-animation.md) |

## Animation graphs

| Value or rule | OpenSky's choice | Page |
| --- | --- | --- |
| Spine `Pitch` sign and `TargetLocation` distance | Not checked against the game | [actor state graph](/engine/actor-state-graph.md) |
| Actor graph update order | OpenSky's order | [actor state graph](/engine/actor-state-graph.md) |
| Damped graph variables | OpenSky's blend and damping rates | [actor state graph](/engine/actor-state-graph.md) |
| Drunk state in a save | Not confirmed | [actor state graph](/engine/actor-state-graph.md) |
| Additive clip order | OpenSky's order | [behaviour runtime](/engine/behavior-runtime.md) |
| Two clip rules | Not confirmed | [behaviour clips](/engine/behavior-clips.md) |
| Animation and skeleton split | A guess from the objects | [HKX behaviour](/formats/hkx-behavior.md) |

## Items, crime, and progression

| Value or rule | OpenSky's choice | Page |
| --- | --- | --- |
| Leveled lock step | One band per 10 player levels, up to Master | [locks](/engine/locks.md#leveled-locks) |
| Lock with no `XLOC` | Level 1 when Papyrus locks it | [locks](/engine/locks.md) |
| Lockpick turn and return speed | 1.5 turns a second, return speed 3 | [locks](/engine/locks.md) |
| Quest items | Marked per base form, not per reference | [inventory menu](/engine/inventory-menu.md) |
| Sell price cap | `fBarterSellMax` 0.95 from the CK settings list; no plugin sets it | [barter](/engine/barter.md) |
| Barter shown price | The movie's use of the multipliers is a guess | [barter](/engine/barter.md) |
| Alchemy value | Before or after perks is not confirmed | [alchemy](/engine/alchemy.md) |
| Werewolf first change | The bounty is counted per faction | [crime](/engine/crime.md) |
| Crime warning timer | OpenSky's reading of `fWarningTimer` | [crime](/engine/crime.md) |
| Jail skill loss | `ceil(18 x days / maximum days)` | [jail](/engine/jail.md) |
| Speech check values | Listed on the page | [speech checks](/engine/speech-checks.md) |
| Perk sky camera vectors and turn speed | OpenSky's numbers | [perk sky](/engine/perk-sky.md) |
| Inventory count step | 10 for up and down | [inventory menu](/engine/inventory-menu.md) |
| `GetGoldValue` for a non-item | -1 | [inventory state](/engine/inventory-state.md) |

## World, time, and sound

| Value or rule | OpenSky's choice | Page |
| --- | --- | --- |
| New game start hour | Midnight | [game clock](/engine/game-clock.md) |
| Time scale ceiling | 10,000 | [game clock](/engine/game-clock.md) |
| Global float to integer | Rounding, not truncation | [global variables](/engine/global-variables.md) |
| Weather global chance | A global that resolves replaces the entry's chance | [weather](/engine/weather.md) |
| Wind speed unit and one setting's meaning | Guesses from xEdit and the name | [weather](/engine/weather.md) |
| Weather global meaning | OpenSky's reading | [weather format](/formats/weather.md) |
| Sun and moon paths | OpenSky's reading of the settings | [celestial sky](/engine/celestial-sky.md) |
| Location tie rule | Inferred | [locations](/formats/locations.md) |
| Terrain with no height | No guessed height | [terrain](/engine/terrain.md) |
| World sound roll interval | OpenSky's interval | [world sounds](/engine/world-sfx.md) |
| Music above a region | Not confirmed | [music](/engine/music.md) |
| Loading screen timing | 1.5 s; 0.4 s fade | [loading screens](/engine/loading-screens.md) |
| Notification timing | Limit of 3 at once | [messages](/engine/messages.md) |
| Movie track, colour matrix, skip keys | First track; BT.601; not confirmed | [movies](/engine/movies.md) |

## Rendering

| Value or rule | OpenSky's choice | Page |
| --- | --- | --- |
| Particle lifetime and limits | OpenSky's policies | [particles](/rendering/particles.md) |
| Image space modifier weights | Two constants; at most 16 at once | [image space](/rendering/image-space.md) |
| Surface shading strength, tiling, refraction rate | OpenSky's values | [surface shading](/rendering/surface-shading.md) |
| Water UV density | 2 quads per repeat | [scene drawing](/rendering/scene-drawing.md) |
| Clear colour under water | OpenSky's choice | [Metal 4 renderer](/rendering/metal4-renderer.md) |
| Light flicker curves, period unit, slow factor | OpenSky's values | [lighting](/formats/lighting.md) |
| Texture scroll rate with no period | OpenSky's rate | [NIF materials](/formats/nif-materials.md) |
| Controller threshold | 0.5 | [NIF controllers](/formats/nif-controllers.md) |
| Particle modifier readings | Items marked "inferred" | [NIF particles](/formats/nif-particles.md) |
| Rotation extra data | Read as thousandths of a radian | [NIF extra data](/formats/nif-extra-data.md) |
| Volume texture depth | 0.5 | [DDS](/formats/dds.md) |
| Distant LOD level limit | `2 x level1`, capped | [distant LOD](/engine/distant-lod.md) |
| First-person shadow rule | OpenSky's rule | [first person](/engine/first-person.md) |
| Main menu smoke and start | Placement checked by eye | [main menu](/engine/main-menu.md) |
| Race menu camera and Age control | OpenSky's framing | [race menu](/engine/race-menu.md) |
| `WarHorseMode` HUD rule | Inferred | [HUD](/rendering/hud.md) |
| `RFCT` rotate-to-face flag | Not used | [visual effects](/rendering/visual-effects.md) |

## Scripts and saves

| Value or rule | OpenSky's choice | Page |
| --- | --- | --- |
| Papyrus VM edge cases | Case, duplicate names, calls on `None`, failed casts | [Papyrus VM](/engine/papyrus-vm.md) |
| `.ess` export fields | Listed as not confirmed | [ESS export](/engine/ess-export.md) |
| Save Papyrus file version | Not confirmed | [ESS Papyrus](/formats/ess-papyrus.md) |
| Save lock flag bit 0x01 | Meaning not confirmed | [locks](/engine/locks.md) |
| `.seq` FormID reading | Through the master list first | [SEQ](/formats/seq.md) |
| Input device for prompts | Not confirmed | [AS2 input](/engine/as2-input.md) |
| Inventory menu callbacks | Two not confirmed | [inventory menu](/engine/inventory-menu.md) |

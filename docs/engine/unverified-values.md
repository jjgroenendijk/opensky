---
type: Reference
title: Unverified values
description: Every value and rule OpenSky chose without a source, with the page that explains it,
  so each one can be checked against the game later.
tags: [engine, verification]
---

# Unverified values

Some numbers and rules have no open source: no record, setting, or wiki page gives them, so
OpenSky picks a value. Each row names the value, OpenSky's choice, and the page with the detail
and its sources, so it can be checked later against the [reference game](/tools/reference-game.md).

## How to use this page

- A change that adds a value without a source adds a row here, and marks the value on its own
  page as OpenSky's choice.
- A row whose value is then confirmed is removed. The source goes on the subsystem page.
- A value that differs from the game, once measured, also needs a `gap` issue (root
  `AGENTS.md`).

## Combat

| Value or rule | OpenSky's choice | Page |
| --- | --- | --- |
| How far apart NPC foes are found | Within 4096 units | [combat loop](/engine/combat.md#npc-foes) |
| NPC foe search in a complex scene | Always 1 to 2 s; the game's complex-scene test is not built | [combat loop](/engine/combat.md#npc-foes) |
| Which race attack spell a creature's blow rolls as its disease | The first Disease spell in the race's `ATKD` list, or in its `ATKR` race's | [Diseases](/engine/diseases.md#where-opensky-differs) |
| How near a death an actor counts as its witness | 2048 units, with no detection check | [combat detection dialogue](/engine/combat-detection-dialogue.md#in-opensky) |
| How long a package waits before it starts again after its walk gave up | 10 s | [package schedules](/engine/package-schedules.md#in-a-session) |
| When a conversation speaker is asked to walk to its partner again | After 1 s in which it moved less than 8 units | [random conversations](/engine/random-conversations.md#where-opensky-differs) |
| Trainer tier thresholds | Journeyman from a maximum of 50, Expert at 75, Master above 75 | [training](/engine/training.md#training-menu) |
| Time-span tag hours | Midnight 23-1, night 1-5, sunrise 5-8, morning 8-12, afternoon 12-17, sunset 17-19, evening 19-23 | [journal](/engine/journal.md#text-replacement) |
| Global tag number format | A whole value as an integer, else two places, whatever the global's type | [journal](/engine/journal.md#text-replacement) |
| `<Global.Meridiem>` words | "AM" and "PM", from no setting | [journal](/engine/journal.md#text-replacement) |
| `fTrackSpeed` unit | Radians per second, a cap on the head-tracking turn speed | [head tracking](/engine/head-tracking.md) |
| Compass marker minimum opacity | 50 percent, at and past `iMapMarkerFadeStartDistance` | [world map](/engine/world-map.md) |
| Music type without `PNAM` | Ranks as priority 100, the lowest | [music](/engine/music.md#scripted-music) |
| `RNAM` reference whose base is not a static, or has no bounds | Stays a large reference without the size test | [distant LOD](/engine/distant-lod.md#large-references) |
| Image space cross-fade curve | Linear rise and fall over the script's fade time | [image space](/rendering/image-space.md#where-opensky-differs) |
| Terrain LOD cut skirt depth | 1000 units per level step: 1000 at level 4 up to 4000 at level 32 | [distant LOD](/engine/distant-lod.md#skirts) |
| Dual power attack stamina | The sum of both weapons' power attack costs | [melee combat](/engine/melee-combat.md#the-left-hand) |
| NPC dual-wield swing order | Right, left, then both, in turn | [melee combat](/engine/melee-combat.md#the-left-hand) |
| Dual strike damage | Each weapon lands one blow on the contact frame, right first | [melee combat](/engine/melee-combat.md#the-left-hand) |
| Melee hit volume | Half height 0.25 x capsule height, radius 0.75 x capsule radius | [melee combat](/engine/melee-combat.md) |
| NPC combo chance | 0.3 per swing, at most 3 swings, no Offensive Mult term | [combat behaviour](/engine/combat-behavior.md) |
| NPC back-off time | At most 2 s | [combat behaviour](/engine/combat-behavior.md) |
| Assistance range | A helper is asked within 2,048 units of its ally; perception tracks only those pairs for the detection check | [combat](/engine/combat.md#who-an-assisting-actor-fights) |
| Resisted-arrest crime window | The 300 seconds after resisting arrest are game seconds, and every fight target counts as having AI | [combat](/engine/combat.md#who-an-assisting-actor-fights) |
| Combat setting formulas | Read from the setting names | [combat](/engine/combat.md) |
| Melee knockdown magnitude | The knockback slide speed over 69.99 | [impulses](/engine/impulses.md#hits) |
| Explosion knockdown magnitude | The `EXPL` force | [impulses](/engine/impulses.md#explosions) |
| Knockdown limb shares | Torso and head 1, upper limbs 0.75, lower limbs 0.5, hands and feet 0.25, by bone name | [ragdoll](/engine/ragdoll.md#knockdown) |
| Get-up fallback blend | 1 s when the graph runs no `hkbGetUpModifier` | [ragdoll](/engine/ragdoll.md#knockdown) |
| `KnockAreaEffect` scale | Magnitude 1 knocks down at 14 Havok m/s | [papyrus session natives](/engine/papyrus-session-natives.md) |
| Actor splash | An actor splashes heavy going in, and not coming out | [impulses](/engine/impulses.md#water) |
| Kill camera timing | OpenSky's numbers | [kill camera](/engine/kill-cam.md) |
| Projectile settings | Formulas read from the setting names | [projectiles](/engine/projectiles.md) |
| Arrow gravity unit | Read as the record value with no scale | [projectiles format](/formats/projectiles.md) |
| Third-person bolt tilt | `f3PBoltTiltUpAngle` falls back to 1 degree, the first-person default | [projectiles](/engine/projectiles.md#range-settings) |
| Trap scales, speed, repeat interval | OpenSky's numbers | [traps](/engine/traps.md) |
| Combat style choice | Not confirmed against the game | [combat style](/formats/combat-style.md) |
| Body parts on the head side of a cut | 30, 31, 41 to 44, 50, 55, 130 to 132, 141 to 143, 150 | [ragdoll](/engine/ragdoll.md#decapitation) |
| Cut head sphere | 10 units radius, 5 kg | [ragdoll](/engine/ragdoll.md#decapitation) |
| Cut head launch | 120 units/s away, 160 units/s up, 6 rad/s turn | [ragdoll](/engine/ragdoll.md#decapitation) |
| Kill cam focus | 96 units above the feet, times the actor's scale; a frame steps the shot by at most 0.1 s | [kill cam](/engine/kill-cam.md) |
| Splash ripple strength | 1 for a heavy splash, 0.6 for the others | [sky and water](/engine/sky-water.md) |
| NPC archer ammunition and shot roll | Needs one arrow and spends none; the shot chance is rolled at the end of each gap between attacks | [archery](/engine/archery.md#npc-archers) |
| Spell-fire fallback | A hand whose graph raises no spell-fire event releases or starts its spell after 0.4 s | [spellcasting](/engine/spellcasting.md#casting-cues) |
| Bounced arrow | Flies on as a harmless projectile and lies where it lands; one that lands on an actor is gone | [projectiles](/engine/projectiles.md#where-opensky-differs) |

## Magic

| Value or rule | OpenSky's choice | Page |
| --- | --- | --- |
| Alpha-0 hit areas | An alpha-0 clip with its own mouse handler catches the pointer; nothing inside an alpha-0 subtree does | [AS2 input](/engine/as2-input.md) |
| Menus that blur the world | The Tween, inventory, and magic menus hold the `IMID` modifier; other menus do not | [Tween menu](/engine/tween-menu.md#blur) |
| Shout card recharge | The recovery time of the last unlocked word, or the first word with none unlocked, times Shout Recovery Mult | [magic](/engine/magic.md#magic-menu) |
| Magic menu tab order | Schools as Alteration, Illusion, Destruction, Conjuration, Restoration, then shouts, powers, active effects | [magic](/engine/magic.md#magic-menu) |
| Cone spell world test | Looks 192 units ahead every 0.125 s and stops at the first surface seen | [spell delivery](/engine/spell-delivery.md) |
| Ward power cap | `strongest ward x (base + mult x Restoration)`, so 1.3 x the stronger ward | [magic archetypes](/engine/magic-archetypes.md) |
| Ward charge-up | A straight line over one second | [magic archetypes](/engine/magic-archetypes.md) |
| Ward order | A ward applies before absorption | [spell delivery](/engine/spell-delivery.md) |
| Ward charge rate and break stagger | OpenSky's numbers | [spell delivery](/engine/spell-delivery.md) |
| Area and range cost terms | Area: `1 + mult x area`; range: a multiplier on aimed and target spells | [spellcasting](/engine/spellcasting.md) |
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
| Update bands | Every frame to 1,024 units, 30 a second to 2,048, 15 a second to 6,144, 5 a second further | [update bands](/engine/update-bands.md#the-bands) |
| Far NPC movement | Waits at most 1/15 s; walk steps of 1/60 s in the `near` band and 1/30 s further out | [update bands](/engine/update-bands.md#systems-that-use-the-bands) |
| Far perception observers | Built again in the update bands, measured from the player | [update bands](/engine/update-bands.md#systems-that-use-the-bands) |
| Encumbrance slowdown | Worn armour weight after perks, `fMoveWeightMin` 0, `SpeedMult` / 100 after it | [walk mode](/engine/walk-mode.md#speed) |
| Fast walk and jog speed | The two interpolation settings, not a fixed 0.25 and 0.5 | [walk mode](/engine/walk-mode.md#speed) |
| Breath time | `fActorSwimBreathBase` + 50 x `fActorSwimBreathMult` seconds | [walk mode](/engine/walk-mode.md#breath-and-drowning) |
| Detection constants | Twelve values, such as a 90-degree half view cone | [detection constants](/engine/detection-constants.md#openskys-own-constants) |
| Crouch visual factor and light level scale | 0.5; one luminance unit is level 100 | [detection](/engine/detection.md) |
| `GetLightLevel` scale | Light level times 100 | [actor natives](/engine/papyrus-actor-natives.md) |
| Horse turn ramp | Starts at 0, adds `iHorseTurnDegreesRampUpPerSecond` each second up to `iHorseTurnDegreesPerSecond`; resets when the turn ends | [riding](/engine/riding.md#steering) |
| Horse sprint drain and HUD | The player's sprint drain at no worn weight; the stamina meter shows the horse's stamina | [riding](/engine/riding.md#sprint-and-stamina) |
| Head tracking | 384 units; angles in degrees; behind angle and neck share | [head tracking](/engine/head-tracking.md) |
| Face morph settings | Units read as seconds; eye offsets as radians | [face morphs](/engine/face-morphs.md) |
| Race morph weight | The race's own TRI target at weight 1 on an assembled head | [head part assembly](/engine/head-part-assembly.md#shape-colour-and-expressions) |
| Navigation | 128-unit ledge rule; 512-unit gait rule | [navigation](/engine/navigation.md) |
| `GetCurrentAIProcedure` of procedures not measured | -1 | [world condition functions](/engine/condition-functions-world.md#packages) |
| Package fallback on a blocked path | A guess at the game's rule | [package schedules](/engine/package-schedules.md) |
| Package steps in one call | 16 deep per actor; a deeper result waits for the next tick | [package schedules](/engine/package-schedules.md#procedure-tree) |
| Scene package wait | A scene does not wait forever on its package | [scenes](/engine/scenes.md) |
| Conversation scene gap | Starts when the conversation ends | [scenes](/engine/scenes.md#conversation-scenes) |
| Conversation scene meeting | Begins when both partners have a loaded body, at any distance | [scenes](/engine/scenes.md#conversation-scenes) |
| Random conversation answer wait | 2 s for the scene of a started quest to take the speaker | [random conversations](/engine/random-conversations.md#where-opensky-differs) |
| Social look and reaction timing | A look lasts 10 s; a walker moves 5 units a second; watchers and finders are searched once a second | [random conversations](/engine/random-conversations.md#where-opensky-differs) |
| Body finder walk limit | A finder gives up its walk after 30 s | [random conversations](/engine/random-conversations.md#where-opensky-differs) |
| Sandbox Allow Conversation default | On when the package sets no value | [sandbox](/engine/sandbox.md) |
| Idle line search miss | The NPC waits the idle-line window before it searches again | [dialogue](/engine/dialogue.md) |
| Follower commands | 0.5 s wait; acts at 128 units | [follower commands](/engine/follower-commands.md) |
| Assault alarm member | The resident member nearest the player | [guard response](/engine/guard-response.md) |
| Default `NAM7` weight | 50 | [actor resolution](/engine/actor-resolution.md) |
| Combat weapon choice | Picked once, not scored again in a fight | [actor resolution](/engine/actor-resolution.md) |
| Idle naming and entry side rules | Read from names seen on the install | [idle runtime](/engine/idle-runtime.md) |
| Hearing range of a combat detection line | 4096 units from the player | [combat detection dialogue](/engine/combat-detection-dialogue.md#in-opensky) |
| Furniture rotation | Reset on standing up | [furniture](/engine/furniture.md) |
| Height limit for arriving at furniture | 128 units | [furniture](/engine/furniture.md#arriving-at-the-seat) |
| Longest wait for the turn to a seat's heading | 3 s, then the actor sits | [furniture](/engine/furniture.md#arriving-at-the-seat) |
| A kept seat with no next package | The actor gets up on the next package pass | [furniture](/engine/furniture.md#sitting-down-and-standing-up) |
| Weapon change while drawn | Sheathe the old hand, then draw the new one | [combat graph names](/engine/combat-graph-names.md) |
| Vehicle trailer and gait clips | An approximation of the game | [vehicles](/engine/vehicles.md) |
| Cart tow line | Spring 6 rad/s at damping 0.35, play 24 units, wheel drag 0.4 per second, front axle swing 7 rad/s at damping 0.5 | [vehicles](/engine/vehicles.md#towing) |
| When a towed cart counts as standing | Speed under 1 unit/s and front axle swing under 0.01 rad/s for 0.5 s, behind a hitch that has not moved | [vehicles](/engine/vehicles.md#where-opensky-differs) |
| Dragon animation | A guess; its graph does not run | [actor animation](/engine/actor-animation.md) |
| Dragon rider target lock | The candidates are taken nearest first; a lock that moves ends the attack order; the notification text is "No target in range."; Switch Target looks 60 degrees | [combat assist](/engine/combat-assist.md#in-opensky) |
| Dismount without race data | 50 units left of the saddle, 65 up | [riding](/engine/riding.md#mounting-and-dismounting) |
| Driven actor stands still | Below 0.5 units per second | [riding](/engine/riding.md) |
| Follower without a Morality value | Morality 3: commits no crime | [package schedules](/engine/package-schedules.md) |
| Package line time | 3 s for a line with no voice length | [package schedules](/engine/package-schedules.md) |
| Aim and light points on a body | A spell aims at the capsule's middle; detection reads light at half the eye height | [detection](/engine/detection.md) |

## Animation graphs

| Value or rule | OpenSky's choice | Page |
| --- | --- | --- |
| Spine `Pitch` sign and `TargetLocation` distance | Not checked against the game | [actor state graph](/engine/actor-state-graph.md) |
| Actor graph update order | OpenSky's order | [actor state graph](/engine/actor-state-graph.md) |
| Damped graph variables | OpenSky's blend and damping rates | [actor state graph](/engine/actor-state-graph.md) |
| Drunk state in a save | Not confirmed | [actor state graph](/engine/actor-state-graph.md) |
| Player attack timing during an attack | The values read at rest, every step | [actor state graph](/engine/actor-state-graph.md#attack-timing) |
| `IsInCastState` on the player | 1 while either hand casts | [actor state graph](/engine/actor-state-graph.md#variables-left-unwritten) |
| Additive clip order | OpenSky's order | [behaviour runtime](/engine/behavior-runtime.md) |
| Two clip rules | Not confirmed | [behaviour clips](/engine/behavior-clips.md) |
| Animation and skeleton split | A guess from the objects | [HKX behaviour](/formats/hkx-behavior.md) |
| Paired idle and kill-move test | An `IDLE` event starting `pa_`, `pa_KillMove` | [paired animations](/engine/paired-animations.md) |
| Fall at an idle start | The player's graph hears no fall or landing on the step that raises an idle, because the idle may move the player | [paired animations](/engine/paired-animations.md#where-opensky-differs) |
| `NPC` and `2_` event prefixes | Come off a paired half's events | [paired animations](/engine/paired-animations.md) |
| Paired animation time limit | 30 s without an end event | [paired animations](/engine/paired-animations.md) |
| NaN in a clip track | Read as the part's identity | [animation](/formats/hka-animation.md) |
| State machine random seed | Seed `0x5EED` for every instance | [state machines](/engine/behavior-state-machines.md#transitions) |
| Pose matching frame heading | Removed about up before matching | [behaviour runtime](/engine/behavior-runtime.md#pose-matching) |
| Pose matching pelvis speed | Live pelvis travel per second, in model space | [behaviour runtime](/engine/behavior-runtime.md#pose-matching) |

## Items, crime, and progression

| Value or rule | OpenSky's choice | Page |
| --- | --- | --- |
| Equip icon of a two-handed weapon | `ES_RIGHT_EQUIPPED`, the right-hand icon | [inventory menu](/engine/inventory-menu.md#list-data) |
| Quest items in jail | They stay on the player in every stay; a real jail hides them from the inventory menu | [jail](/engine/jail.md#the-two-parameters-in-the-game) |
| Lockpick widening per broken pick | Counts the picks broken on the open lock only | [locks](/engine/locks.md) |
| Ingredient use settings | Not read: the install adds 0 uses, so no effect is ever taught | [alchemy](/engine/alchemy.md) |
| Tempering skill use | Condition gain from `fHealthDataValue1`, one step per level | [crafting](/engine/crafting.md) |
| Made enchantment default name | The base names joined by ` + ` when the player gives none | [enchanting](/engine/enchanting.md#enchanting-menu) |
| Forge tab of each material keyword | Iron banded, steel plate, scaled, Stormcloak, dragonplate, dragonscale, and dragonbone as listed; other materials, such as silver and the Dawnguard sets, go under Misc | [crafting](/engine/crafting.md#crafting-menu) |
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
| Tab of a carried light (torch) | Misc | [inventory menu](/engine/inventory-menu.md) |
| When the skills menu text fades in | As the menu opens, with the camera rise | [perk sky](/engine/perk-sky.md) |
| `GetGoldValue` for a non-item | -1 | [inventory state](/engine/inventory-state.md) |
| Kill stat of an actor | Its `ActorType*` keywords on the race or the base pick the stats; one kill can raise two | [statistics](/engine/statistics.md#how-opensky-counts) |
| Potions Mixed per brew | One per brew, whatever number of potions it makes | [statistics](/engine/statistics.md#how-opensky-counts) |
| Skill Increases from training | Training counts, one per level the skill rises | [statistics](/engine/statistics.md#how-opensky-counts) |
| Books Read | A note counts, and only the first reading of each book counts | [statistics](/engine/statistics.md#how-opensky-counts) |
| Spells Learned | Only a spell tome counts, not a spell a script adds | [statistics](/engine/statistics.md#how-opensky-counts) |
| Gold Found | Only gold taken from the world, a container, or a body | [statistics](/engine/statistics.md#how-opensky-counts) |
| Chests Looted | Every opening of a container counts, a sack or a barrel too | [statistics](/engine/statistics.md#how-opensky-counts) |
| Ingredients Harvested | One per ingredient a harvest gives, so a perk that doubles the harvest doubles the count | [statistics](/engine/statistics.md#how-opensky-counts) |
| Dungeons Cleared | Every location that clears counts, by its last boss or by `Location.SetCleared` | [statistics](/engine/statistics.md#how-opensky-counts) |

## World, time, and sound

| Value or rule | OpenSky's choice | Page |
| --- | --- | --- |
| Under-the-world placement | A spot with a surface above it and no ground within 4,096 units below stands on the surface above | [player camera](/engine/player-camera.md) |
| New game start hour | Midnight | [game clock](/engine/game-clock.md) |
| Launcher start places | Map markers of type City, Town, Settlement, Orc Stronghold, the nine hold Capitol types, Raven Rock, and Tel Mithryn | [main menu](/engine/main-menu.md#new-game-at-a-chosen-place) |
| Time scale ceiling | 10,000 | [game clock](/engine/game-clock.md) |
| Random door landing | 150 units along the target door's +Y axis, automatic doors too | [random doors](/engine/random-doors.md#in-opensky) |
| Largest loaded cell grid | 10 rings (`uGridsToLoad` 21) | [cell streaming](/engine/cell-streaming.md) |
| Sound purge ring | One ring past the loaded grid | [audio](/engine/audio.md) |
| Global float to integer | Rounding, not truncation | [global variables](/engine/global-variables.md) |
| Weather global chance | A global that resolves replaces the entry's chance | [weather](/engine/weather.md) |
| Wind speed unit and one setting's meaning | Guesses from xEdit and the name | [weather](/engine/weather.md) |
| Weather global meaning | OpenSky's reading | [weather format](/formats/weather.md) |
| Location tie rule | Inferred | [locations](/formats/locations.md) |
| Terrain with no height | No guessed height | [terrain](/engine/terrain.md) |
| Current push speed cap | The swim speed while swimming, else the run speed | [water physics](/engine/water-physics.md#actors-in-a-current) |
| Cell water box floor | The lowest land height of the cell; 4096 units deep without land | [water physics](/engine/water-physics.md#where-the-boxes-come-from) |
| Shaped current positions | Read as Havok units | [water physics](/engine/water-physics.md#current-lists) |
| World sound roll interval | OpenSky's interval | [world sounds](/engine/world-sfx.md) |
| Music above a region | Not confirmed | [music](/engine/music.md) |
| Loading screen light falloff | 1, as a `LIGH` record with none | [loading screens](/engine/loading-screens.md) |
| Loading screen arrow keys | The stick at full tilt while held | [loading screens](/engine/loading-screens.md) |
| Longest frame a loading screen turn counts | 0.1 s | [loading screens](/engine/loading-screens.md) |
| Longest wait for the start area under a load or new-game cover | 90 s | [loading screens](/engine/loading-screens.md) |
| Notification timing | Limit of 3 at once | [messages](/engine/messages.md) |
| Movie colour matrix | BT.601; the only vanilla movie is grey, so it cannot tell BT.601 from BT.709 | [movies](/engine/movies.md#drawing) |
| Custom marker aim and questions | 5% of the map camera height; the question order | [world map](/engine/world-map.md#custom-marker) |
| Speaker matrix on two speakers | Centre and surrounds add at -3 dB, LFE dropped, the mono row only | [sound output](/formats/sound-output-reverb.md#output-model-mapping) |
| Special music triggers | Level up with the notice, cleared with the notice, death when the player dies | [music](/engine/music.md#special-music) |
| Fast travel walk speed fallback | 80 units per second when no movement type gives one | [world map](/engine/world-map.md) |
| Convex radius corners | A box, hull, or cylinder grows by its convex radius with sharp edges and corners, where Havok rounds them | [NIF collision](/formats/nif-collision.md#convex-radius) |
| Cylinder convex radius | The radius widens the wall and lengthens both ends, as for the other convex shapes | [NIF collision](/formats/nif-collision.md#convex-radius) |

## Rendering

| Value or rule | OpenSky's choice | Page |
| --- | --- | --- |
| Far particle systems | Stepped in the update bands, waiting at most 1/15 s | [update bands](/engine/update-bands.md#systems-that-use-the-bands) |
| Grass near lists | The draw distance plus 1,024 units, built again after the camera moves 512 to 1,024 units | [update bands](/engine/update-bands.md#grass) |
| Actor camera fade bodies | A bone body's node bound is half its length plus its radius; a movement capsule's bound is half its height; a hull is the sphere around its points | [actor camera fade](/engine/actor-camera-fade.md#opensky) |
| Indirect light blur weights | A Gaussian of deviation 7 / 3 over the 15 taps | [post effects](/rendering/post-effects.md#indirect-light) |
| Far shadow cascade reuse | A far cascade map kept while it covers its slice, at most 2 or 4 frames, 0.25 degrees of sun turn, 10% wider fit | [shadows](/rendering/shadows.md#far-cascade-reuse) |
| Particle lifetime and limits | OpenSky's policies | [particles](/rendering/particles.md) |
| Interface HTML text lines | A line's height and baseline come from the field's own font and size, whatever size its `<font>` tags set | [SWF text](/formats/swf-text.md#html-text) |
| Interface filters | A shadow, glow, or blur of 1.5 pixels or more draws 8 copies on an ellipse of half the blur, which together reach 0.99 alpha; the shadow alpha is the colour alpha times the strength, at most 1 | [SWF render layer](/rendering/swf-layer.md#filters-and-blend-modes) |
| Interface line strokes | A line thinner than 20 twips (one pixel) draws 20 twips wide; round caps and joins step until the arc strays at most 1 twip; overlapping pieces of a translucent line blend twice | [SWF shapes](/formats/swf-shapes.md#strokes) |
| Lightning bolt between sequences | A sequence that leaves the generation unset keeps the bolt, its tree, and its track values; at most 2,048 quads per bolt tree | [particles](/rendering/particles.md#lightning) |
| Ribbon texture direction | U along the band for strips | [particles](/rendering/particles.md#ribbons) |
| Particle sequence switch | A played sequence restarts the controllers it feeds from 0; others keep the default sequence's keys | [particles](/rendering/particles.md#sequences) |
| Rain streak shape | Length over width from the `SPGD` size Y over X, 1 to 16, with the square's area | [precipitation](/rendering/precipitation.md#streaks) |
| Strip particle order | One band through the particles in birth order | [particles](/rendering/particles.md#ribbons) |
| Mesh particle size | The particle size scales the pool mesh | [particles](/rendering/particles.md#mesh-particles) |
| Billboard minimised turn (modes 0, 3) | Shortest turn of own +Z to the target, from nif.xml's "minimized rotation" | [NIF sequences](/formats/nif-sequences.md#billboard-nodes) |
| Billboard shadow | A rigid shape below a billboard casts no sun shadow | [scene drawing](/rendering/scene-drawing.md#billboard-shapes) |
| Image space modifier weights | Two constants; at most 16 at once | [image space](/rendering/image-space.md) |
| Radial blur shape | 8 taps reaching `strength` percent to the centre; radius as a share of centre-to-corner; centre in 0-1 screen units | [image space](/rendering/image-space.md#blur-effects) |
| Motion blur trail | Camera turn only; 3 × `s / (1 - s)` frames, capped at a tenth of the screen | [image space](/rendering/image-space.md#blur-effects) |
| Bloom pattern | Three rings of 8 taps; 4 pixels per radius step at 1080; receive threshold unused | [image space](/rendering/image-space.md#bloom-and-light-scales) |
| Sunlight and sky scale | Applied only with the HDR target; sky scale skips clouds | [image space](/rendering/image-space.md#bloom-and-light-scales) |
| Shadow lights at once | 4 nearest the camera, skipped past 4,096 units outside the sphere; 512-texel faces | [shadows](/rendering/shadows.md#point-light-shadows) |
| Point shadow planes and bias | Near plane 8 units; 2-unit normal offset, times the `XLIG` depth bias | [shadows](/rendering/shadows.md#point-light-shadows) |
| Water refraction | Normal x, y times the refraction magnitude in screen units, scaled by depth to the fog far plane | [water](/rendering/water.md#refraction) |
| Water rings | Closed-form crests; 8 rings of 3 s; wading ring every 48 units at strength 0.4, under 150 units deep; floors 8, 4, 0.2 | [water](/rendering/water.md#displacement-and-rain) |
| Rain rings | 48-unit grid, 0.8 s drops, 24-unit rings | [water](/rendering/water.md#displacement-and-rain) |
| Water flow speed | Flow noise scrolls 0.001 tiles a second per rate step | [water](/rendering/water.md#flow-maps) |
| Flow map plugin folder | The newest plugin folder with the cell's file | [water](/rendering/water.md#flow-maps) |
| Water noise falloff | Normals fade in a straight line to flat at the falloff distance | [water](/rendering/water.md#where-opensky-differs) |
| Under-water fog colour | The deep colour | [water](/rendering/water.md#under-the-water) |
| Surface shading strength, tiling, refraction rate | OpenSky's values | [surface shading](/rendering/surface-shading.md) |
| Reference fade timing | A distance dissolve from value 0.7 to 0.3 for the timed 2 s and 1.2 s fades | [graphics options](/engine/graphics-options.md#reference-fade) |
| `BSLODTriShape` level counts | Prefixes when falling, else runs | [NIF](/formats/nif.md#nitrishape) |
| Rain occlusion depth range | 6,000 units above the camera to 4,000 below, straight down | [precipitation](/rendering/precipitation.md#roof-occlusion) |
| Water screen-space reflection march | 24 steps from 24 units, each 1.25 times longer | [water](/rendering/water.md#screen-space-reflections) |
| Water screen-space reflection length fade | Zero at one screen of distance | [water](/rendering/water.md#screen-space-reflections) |
| Snow sparkle colour | The sun colour | [terrain](/engine/terrain.md#snow-ground) |
| Directional material overlay | Drawn inside the shape, lit by the shape's terms; texture frame across the direction, with world y as its first axis | [surface shading](/rendering/surface-shading.md#directional-materials) |
| Skin decal size and limit | At most 16 units; 35 kept when unset | [decals](/rendering/decals.md#skin-decals) |
| Sky gradient heights | Horizon colour at 0 degrees, sky-lower at 17.5, sky-upper from 35 | [celestial sky](/engine/celestial-sky.md#drawing) |
| Depth of field target focus ring | 8 points 5 percent of the screen from the centre; the centre weight times 8 against them | [post effects](/rendering/post-effects.md#focus-on-the-view-centre) |
| Character light luminance | Eye adaptation luminance as the scene value `L` | [surface shading](/rendering/surface-shading.md#character-light) |
| Camera far plane | 350,000 units: the LOD reach plus half a level-32 block; the game's own far plane is not known | [coordinates](/decisions/coordinates.md#nearfar-planes-at-skyrim-scale) |
| Terrain split distance | `fSplitDistanceMult` scales the level 4, 8, and 16 reach; level 32 keeps `fBlockMaximumDistance` | [graphics options](/engine/graphics-options.md) |
| Large reference LOD hidden per block | The game's per-cell rule is not known | [distant LOD](/engine/distant-lod.md#large-references) |
| Ambient occlusion fade | Fades out between 2,048 and 4,096 units from the camera | [post effects](/rendering/post-effects.md#ambient-occlusion) |
| Ambient occlusion blur edge | A tap 5 percent nearer or farther than the pixel counts for nothing | [post effects](/rendering/post-effects.md#ambient-occlusion) |
| Eye adaptation quarters | the four quarter values blend linearly between the quarter centres; checked with capture pairs only | [image space](/rendering/image-space.md#hdr-tone-mapping) |
| Volumetric light steps | 8, 16, 32 steps by quality | [post effects](/rendering/post-effects.md#volumetric-light) |
| `VOLI` field scales | cell 64 × size; drift 4 × wind along X; fall 64 × falling; noise fade over 150 units above the camera; near plane 15; fallback values for interiors | [post effects](/rendering/post-effects.md#volumetric-light) |
| Depth of field blur | Clear at distance, full at range; `2 + 2 × radius` pixels at 1080 lines, radius 3 without a code; modifier moves toward its value | [post effects](/rendering/post-effects.md#depth-of-field) |
| `IMGS` `DNAM` blur code | High half of float `2 + 4n`; radius `n / 2`, odd `n` is No Sky | [image spaces](/formats/image-spaces.md#depth-of-field) |
| Lens flare pattern | 5 ghosts, strength 0.6 times sun alpha and weather Sun Glare, 9 visibility taps | [post effects](/rendering/post-effects.md#lens-flare) |
| Water UV density | 2 quads per repeat | [scene drawing](/rendering/scene-drawing.md) |
| Clear colour under water | OpenSky's choice | [Metal 4 renderer](/rendering/metal4-renderer.md) |
| Light flicker curves, period unit, slow factor | OpenSky's values | [lighting](/formats/lighting.md) |
| Texture scroll rate with no period | OpenSky's rate | [NIF materials](/formats/nif-materials.md) |
| Controller threshold | 0.5 | [NIF controllers](/formats/nif-controllers.md) |
| Path bank sign and bend measure | Rolls with the turn's sign; bend is heading change per unit length | [NIF controllers](/formats/nif-controllers.md#node-controller-rules) |
| Particle modifier readings | Items marked "inferred" | [NIF particles](/formats/nif-particles.md) |
| Rotation extra data | Read as thousandths of a radian | [NIF extra data](/formats/nif-extra-data.md) |
| Distant LOD level limit | `2 x level1`, capped | [distant LOD](/engine/distant-lod.md) |
| First-person shadow rule | OpenSky's rule | [first person](/engine/first-person.md) |
| Main menu smoke and start | Placement checked by eye | [main menu](/engine/main-menu.md) |
| Race menu camera | OpenSky's framing | [race menu](/engine/race-menu.md) |
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
| Gamepad look sensitivity | The default sensitivity at the middle of OpenSky's Look Sensitivity slider, scaled with it, kept inside the game's range | [AS2 input](/engine/as2-input.md#gamepads-in-the-world) |
| Auto-Move end | Pressing Auto-Move again, Forward, or Back ends it | [control map](/formats/controlmap.md#the-controls-list) |
| Mouse button art | Mouse button `n` (0 the left) shows `Mouse<n+1>` | [control map](/formats/controlmap.md#the-controls-list) |
| Inventory menu callbacks | Two not confirmed | [inventory menu](/engine/inventory-menu.md) |
| Topic row prompt of a shared `INFO` | Own `RNAM`, else the shared target's | [dialogue](/engine/dialogue.md) |
| Follower place after a load door | 64 units apart beside the player | [follower commands](/engine/follower-commands.md#load-doors) |
| Projectile model facing and lights | `PROJ` model +Y along the velocity; flight light at full colour; muzzle flash light fades linearly over the flash duration | [spell delivery](/engine/spell-delivery.md#what-a-projectile-shows) |
| Explosion light and impact | `EXPL` light for 2 s, fading linearly; impact data set played on no material | [explosions](/formats/explosions.md#runtime) |
| Casting light position | In front of the caster's eye, where a held Light spell floats | [spellcasting](/engine/spellcasting.md) |
| Face-target aim point | The facing object's origin, an actor's feet | [visual effects](/rendering/visual-effects.md#where-effects-come-from) |
| Creature loop reach and count | Loops play for the nearest 8 actors within 3000 units | [creature sounds](/engine/actor-sounds.md#loops) |
| Creature conscious loop state | Stops while the actor is unconscious | [creature sounds](/engine/actor-sounds.md#loops) |
| Music and dialogue duck levels | Music falls to 0.4 and `SFDC`/`NDSC` sounds to 0.5 in a conversation; `SFDC`/`NDSC` fade over the music seconds | [sound mix](/engine/sound-mix.md#what-a-category-does) |
| Sound rumble bus level | The sum of each sound's `LNAM` send times its heard level, master volume included | [sound mix](/engine/sound-mix.md#rumble) |
| Weapon rumble timing | Every blow the player's weapon lands | [sound mix](/engine/sound-mix.md#rumble) |
| Body collision sound | A speed loss of 150 units/s is a hit; level 0.25 to 1 up to a loss of 800; 15 quiet steps | [impulses](/engine/impulses.md#collision-sounds) |
| Tree sway and leaf flutter | `treeSwayTilt` 0.1, leaf side share 0.5, leaf fade at 4096 units, defaults leaf amplitude 3 and frequency 1 | [trees](/rendering/trees.md) |
| Skin decal projection depth | The box reaches as far in front of and behind the decal as its widest half side | [decals](/rendering/decals.md#skin-decals) |
| Skin decal bone | The body bone with the nearest origin to the hit; weapon, shield, quiver, camera, magic, arrow, and root nodes skipped | [decals](/rendering/decals.md#skin-decals) |
| Static idle random roll | 12 steps, rolled when the idle is chosen, for an actor that runs no graph | [idle runtime](/engine/idle-runtime.md#playback) |
| Line speaker and listener idles | Both start with the line, without the idles' own conditions | [scenes](/engine/scenes.md#idles) |
| Package idle list | Plays only while the actor stands still and has no marker | [idle runtime](/engine/idle-runtime.md#package-idles) |
| Player shove efficiency | 0.175 of the player's momentum, before the game's mass and layer factor | [dynamic bodies](/engine/dynamic-bodies.md#the-players-shove) |
| Contact warm start | A contact within 2 units of last substep's starts with 90% of its impulse; passes alternate direction | [dynamic contacts](/engine/dynamic-narrowphase.md#warm-starting) |
| Swim settle | A rising swimmer stops at the 10-unit rest depth; above it, gravity pulls the float point back down | [walk mode](/engine/walk-mode.md#gaits-jump-and-swim) |
| Walk step height | 36 units, though the game has none; the plank stairs of Riften have risers of up to 33.2 units | [walk mode](/engine/walk-mode.md#settings) |
| Long body end lift | End spheres ride 32 units, the walk step height, above the feet | [character shapes](/engine/character-shapes.md#long-bodies) |
| Swim breadcrumb trail | A point every 128 units, the last 64 kept; joined within 1,024 units, serves targets within 512 of its end | [navigation](/engine/navigation.md#swimming-after-the-player) |
| Already-known tome notice | `sAlreadyKnown`, a space, the spell name, and a full stop | [spellcasting](/engine/spellcasting.md#reading-a-tome) |
| Alchemy craft button | Shown with two or more chosen ingredients, whether or not they share an effect | [crafting](/engine/crafting.md#buttons-and-questions) |
| Load door name | Interior: the far cell's `FULL`; exterior: the worldspace's `FULL`, never the cell's | [interaction](/engine/interaction.md#load-doors) |
| Inline picture height | The bottom of an `<img>` picture sits on the baseline; a negative `vspace` moves it down | [AS2 display runtime](/engine/as2-display-runtime.md#text) |
| Menu controller count | One controller, GFx's default, whatever is connected | [AS2 input](/engine/as2-input.md#who-sets-the-focus) |
| Tween camera turn direction | Skills turns the view up, Magic left, Items right, and Map down, as the entries sit | [Tween menu](/engine/tween-menu.md#camera) |
| Installed Content list | Always the seven-entry `HMCC` list, never the Anniversary Edition `HMAE` one | [system menu](/engine/system-menu.md#help-and-installed-content) |
| Spell card effect lines | Each shown effect's description, joined with one space | [magic](/engine/magic.md#magic-menu) |
| Spell card numbers | A whole number shows no decimals; any other shows up to two | [magic](/engine/magic.md#magic-menu) |
| Spell card `castTime` | 1 for a spell that is not concentration; the movie only tests for 0 | [magic](/engine/magic.md#magic-menu) |
| Loading screen image space | A loading screen draws through `LSIS`, as the main menu does; the name says so, but only the main menu was read. The world's modifiers and screen fade are left out | [loading screens](/engine/loading-screens.md#image-space) |
| Favourite tie | Two forms used as often: the one used last wins; the game leaves the order open | [general stats](/engine/statistics.md#how-opensky-counts) |
| Favourite weapon uses | Each melee swing and bow or crossbow shot; staves and scrolls do not count | [general stats](/engine/statistics.md#how-opensky-counts) |
| Shouts Learned | A taught word counts for a shout the player could not use before; the game's "adds a shout" check is read that way | [general stats](/engine/statistics.md#how-opensky-counts) |
| Conversation scene meeting | A pair may walk together for 30 s; after that its scene waits 60 s before it tries again; a meeting no scene asks for in 2 s ends | [scenes](/engine/scenes.md#conversation-scenes) |
| Scene line facing wait | A line waits at most 3 s for its speaker to turn to the listener | [scenes](/engine/scenes.md#conversation-scenes) |
| Dodge limit | A fighter dodges at any threat score above 0; the game's limit is not known | [danger avoidance](/engine/danger-avoidance.md#in-opensky) |
| Dodge move speed | 370 units a second times the move of a sidestep for every actor | [danger avoidance](/engine/danger-avoidance.md#in-opensky) |
| Avoid Threat Chance default | 0.2 for a combat style that leaves the value out | [danger avoidance](/engine/danger-avoidance.md#in-opensky) |
| Auto-aim window axis | The window is measured against the screen height on both axes | [combat assist](/engine/combat-assist.md#in-opensky) |
| Long body end lift | The end spheres of a long body ride one step height above the ground | [character shapes](/engine/character-shapes.md#long-bodies) |
| Aggro warning line | An actor that warns by its aggro radius says a line of the Trespass subtype | [combat behavior](/engine/aggro-radius.md) |
| NPC weapon draw time | An NPC takes 0.5 s to draw and 0.5 s to sheathe; the game times both by the clips. A graph that reports `IsEquipping` holds the draw at most 2 s longer | [condition functions](/engine/condition-functions-world.md#combat-actions) |
| Follower command busy wait | A follower that cannot start its walk is asked again for 10 s, then the order ends | [follower commands](/engine/follower-commands.md) |
| Melee magnetism signs and look scale | Both terms turn toward the target; the look input is the frame's view turn, scaled by a turn speed of 2π rad/s; an object counts within 192 units | [combat assist](/engine/combat-assist.md#in-opensky) |
| Alarm flee distance | An NPC criminal that a guard answers runs 2000 units straight away from the guard, along the ground | [crime reports](/engine/crime-reports.md#where-opensky-differs) |
| Bribe cost text | `<BribeCost>` shows the bribe amount rounded down to whole gold, as `Actor.GetBribeAmount` returns an integer | [dialogue menu](/engine/dialogue-menu.md#text) |
| Dialogue edge look speed unit | `fPCDialogueLookSpeed` 10 is read as 10 pointer points of look input per 1/60 s | [dialogue camera](/engine/dialogue-camera.md) |
| When an explosion points almost straight down | Its unit direction has a z below -0.95 | [explosions](/engine/explosions.md#damage) |
| Explosion line of sight width | A sphere of radius 1 swept from the start to the actor | [explosions](/engine/explosions.md#damage) |
| Stage debris force | A destruction stage throws its debris with a force of 100 | [destruction](/engine/papyrus-destruction.md#in-the-game) |
| Ignore External Damage hold | Damage that is not forced leaves the health 0.001 percent above the flagged stage | [destruction](/engine/papyrus-destruction.md#in-the-game) |
| Wider kill cam target search | With no aim help target, an actor counts when the aim line passes within its capsule radius plus 32 units | [kill cam](/engine/kill-cam.md#bow-and-spell-kill-cams-in-the-game) |
| Physics impact reach on objects | A fast body checks the destructible objects whose origin is within its bounding radius plus 128 units | [destruction](/engine/papyrus-destruction.md#where-opensky-differs) |
| Placed explosion object rotation | Pitch tips it along the flight's rise and the heading turns clockwise from north to the flight; there is no roll | [explosions](/engine/explosions.md#where-opensky-differs) |
| Placed explosion object owner | The crime owner of the explosion's source: the destroyed reference, or else the shooter | [explosions](/engine/explosions.md#where-opensky-differs) |
| Stage explosion offset | A uniform random direction, times a uniform random share of the bound radius | [destruction](/engine/papyrus-destruction.md#in-the-game) |
| Spell kill cam damage | The release check sums the spell's harmful Health value modifiers, before resistance | [kill cam](/engine/kill-cam.md#bow-and-spell-kill-cams-in-the-game) |
| Damage stage node range | A `BSDamageStage` node shows from its minimum to its maximum stage, both included | [NIF](/formats/nif.md) |
| Enchanting slider opening | The magnitude slider opens when a weapon base is chosen while a weapon is chosen | [enchanting](/engine/enchanting.md#enchanting-menu) |
| Enchanting slider base | With two bases, the slider's maximum comes from the first base's first effect | [enchanting](/engine/enchanting.md#the-magnitude-slider-in-the-game) |
| Made apparel cost | A made apparel enchantment stores the weapon cost formula at the soul's share of the maximum, for its value | [enchanting](/engine/enchanting.md#the-magnitude-slider-in-the-game) |
| Enchanting spell cost tab | `Mod Spell Cost` on an enchantment base binds the base to the spell tab | [enchanting](/engine/enchanting.md#the-magnitude-slider-in-the-game) |
| Made value and temper | A tempered copy's value multiplier applies after a made enchantment's worth is added | [enchanting](/engine/enchanting.md#the-magnitude-slider-in-the-game) |
| Vendor stock order | A buy takes the chest's copies before the vendor's own, and a sale pays from the chest's gold first | [vendor factions](/engine/vendor-factions.md#stock-gold-and-what-a-vendor-takes-in-the-game) |
| Vendor's worn items | The vendor's own side leaves out the items it wears | [vendor factions](/engine/vendor-factions.md#stock-gold-and-what-a-vendor-takes-in-the-game) |
| Copy row stolen count | A row per copy counts the stolen copies from the plainest row up | [item copies](/engine/item-copies.md#names-and-poisons-in-the-game) |
| Weapon attack loop end | The `WEAP` `NAM7` loop stops on the `attackStop` animation event | [item records](/formats/item-records.md) |

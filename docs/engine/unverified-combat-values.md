---
type: Reference
title: Unverified combat values
description: The combat values and rules OpenSky chose without a source, with the page that
  explains each one.
tags: [engine, verification, combat]
---

# Unverified combat values

The combat part of the [unverified values](/engine/unverified-values.md) list. The same rules
apply: each row names the value, OpenSky's choice, and the page with the detail.

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
| Close-range move arrival | A back off, circle, or fallback has arrived within 32 units of its point | [combat style](/formats/combat-style.md#where-opensky-differs) |
| Close-range move timeout | A close-range move that has not arrived after 5 s fails | [combat style](/formats/combat-style.md#where-opensky-differs) |
| Target moving away | A target moves away when its speed away from the actor is above 1 unit a second | [combat style](/formats/combat-style.md#where-opensky-differs) |
| Bare-hand block | Bare hands block only with a shield, and never bash | [combat blocking](/engine/combat-blocking.md#in-opensky) |
| Block attack distance | The per-fighter distance is both actors' radii | [combat blocking](/engine/combat-blocking.md#in-opensky) |
| `CSME` bash defaults | A missing bash value reads as 1 | [combat blocking](/engine/combat-blocking.md#in-opensky) |

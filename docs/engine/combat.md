---
type: Subsystem
title: Combat loop
description: Hostility, derived combat state, the scripted dev target that fights back,
  hit reactions in both directions, transient caps, and the combat-music edge.
tags: [engine, combat, hostility, dev-target, npc, music, persistence]
timestamp: 2026-08-08T00:00:00Z
---

# Combat loop

Roadmap item 15.7 (issue #374). Items 15.3 to 15.6 built the pieces of a fight —
values that can be taken off, a swing that takes them, an arrow that flies, a
corpse that falls and can be looted. Each is complete on its own and none of them
makes a fight, because nothing decided who was fighting whom, and nothing hit
back. This page is that decision layer.

Impl: `opensky/Engine/Combat/CombatLoop*.swift`,
`opensky/Engine/Combat/DevTargetDriver.swift`,
`opensky/Engine/Combat/CombatTransientLimits.swift`,
`opensky/Engine/Actors/ActorCombatComponent.swift`, plus
`opensky/App/GameViewControllerCombat.swift` and its two satellites.

The pieces it ties together: [melee combat](/engine/melee-combat.md),
[archery and projectiles](/engine/archery.md),
[death and ragdoll](/engine/ragdoll.md), [actor values](/engine/actor-values.md),
[dynamic rigid bodies](/engine/dynamic-bodies.md), [music](/engine/music.md).

## Contents

* [What this is not: AI](#what-this-is-not-ai)
* [Hostility](#hostility)
* [Combat state is derived](#combat-state-is-derived)
* [The dev target](#the-dev-target)
* [Reactions in both directions](#reactions-in-both-directions)
* [Reaction clips](#reaction-clips)
* [Transient caps](#transient-caps)
* [Combat music](#combat-music)
* [Measured cost](#measured-cost)
* [Persistence](#persistence)
* [Panel seam](#panel-seam)
* [Limits](#limits)

## What this is not: AI

The opponent in this milestone is a **clock**, and the code says so at length.

A real opponent perceives, decides, paths, and picks an attack. None of that
exists yet: NPCs are render-only with single-clip playback
([actor animation](/engine/actor-animation.md)), they carry no behavior graph,
and trigger occupancy is player-capsule-only. Building half an AI here to make
the milestone's fight happen would put a second, worse decision layer in the
engine that M16 would then have to remove.

So the dev target attacks on a fixed interval, from wherever it is standing, at
whatever is in front of it. It does not chase, it does not choose, and it does
not give up. What it *does* do is go through the shipping paths — the 15.4 hit
volume, the 15.4 damage formula, the 15.3 actor-value store — so everything
downstream of "an opponent hit the player" is the real thing and stays the real
thing when M16 replaces the clock with a mind.

`CombatLoopRuntimeTarget.swift` is the file M16 replaces.

## Hostility

One enum per actor, `ActorHostility`, stored as the `ActorCombatState` component
and therefore journalled, dirty-counted and saved like every other world-state
write ([runtime state](/engine/runtime-state.md)).

| Case | Meaning |
| --- | --- |
| `neutral` | The actor has no quarrel with the player. Every actor starts here. |
| `hostile` | The actor fights the player. |

There is deliberately no `dead` case: death is `ActorDeathState.isDead`, and a
second spelling of the same fact is a second thing to keep in agreement.

Hostility is entered exactly two ways:

1. **The player hurt it.** `CombatLoopRuntime.provoke(_:)` is called from the
   melee hit path and from the projectile impact path, so a swing and an arrow
   anger a target identically. It is idempotent, so each caller can call it
   without checking first.
2. **The panel toggle.** `CombatLoopControlProviding.selectedActorIsHostile`.

There is no aggro radius, no faction relation, no disposition arithmetic and no
crime. Those need perception and packages, and both are M16's.

## Combat state is derived

"Is the player in combat" is **not stored**. It is derived every fixed step from
the resident actor list: in combat means *some resident actor is hostile and
alive*, and the current target is the nearest of those, ties broken on the lower
`ReferenceKey`.

Deriving it is what keeps it honest. A target that died, a cell that unloaded,
and a hostility cleared from the panel all change the answer on the next step
with nothing to invalidate. A stored flag would have to be cleared from each of
those places, and the one that was forgotten would leave the player permanently
in combat with a corpse.

Nearest rather than most-recently-hit, because both consumers — the music edge
and the combat-target condition run-on — want "who am I fighting", and a player
who turned to face a second attacker has answered that by turning.

## The dev target

`DevTargetDriver` is a pure value advanced by one fixed step at a time, so a run
at 60 frames a second and a run at 144 produce the same fight.

| Phase | Leaves it after | Notes |
| --- | --- | --- |
| `idle` | `intervalSeconds` (1.6 s) | The gap between attacks. |
| `windup` | `windupSeconds` (0.45 s) | Attack clip playing, nothing connected. |
| `contact` | one step | The hit volume runs here, once. |
| `recovery` | `recoverySeconds` (0.35 s) | No new attack starts. |
| `staggered` | `staggerSeconds` (0.7 s) | A hit took the attack away. |

Every number above is **OpenSky's, not Bethesda's**. No record states an attack
cadence; vanilla's comes from the combat AI this item deliberately does not
build. They are chosen slow enough that a player can block, draw a bow, and watch
what happened between blows.

The phases mirror the player's own (`MeleeCombatState`) on purpose, so the two
sides of a fight are legible against each other, and a stagger takes the attack
away exactly as the graph's own stagger transition does for the player.

Two things the stand-in does that a real opponent would do differently, stated
rather than hidden:

* **It turns to face the player at the contact step.** The placement facing an
  ACHR carries is where the level designer pointed it, which is almost never at
  whoever walked in; without the turn the stand-in would swing at a wall forever.
* **It never moves.** A player who steps out of reach is safe, permanently.
  NPC locomotion needs the behavior graph M16 brings, and faking a slide toward
  the player would put movement in the engine nothing else agrees with.

## Reactions in both directions

The target staggers, the player recoils.

* **Target staggered.** A landed player hit calls
  `CombatLoopRuntime.noteStagger(of:)`, which interrupts the driver and plays the
  stagger clip. The 15.4 path also raises `staggerStart` on the target's graph,
  which answers false because NPCs have none — the readout records that rather
  than assuming a reaction played.
* **Player recoiled.** A landed opponent blow writes `recoilMagnitude` and then
  raises `recoilStart` on the player's graph, in that order, so the recoil
  behavior reads this blow's number rather than the previous one's. The same
  write-then-raise order the melee runtime uses for a stagger.

`recoilStart`, `recoilStop`, `recoilLargeStart`, `IsRecoiling` and
`recoilMagnitude` are all quoted from the behavior census over the user's own
install, not from memory: the third-person `0_master.hkx` declares all five.
`recoilLargeStart` is deliberately left unraised — which magnitude selects the
heavier variant is a threshold no open source states, and guessing it would play
the wrong reaction.

The HUD's damage flash is a hook, not a drawn effect:
`CombatLoopRuntime.playerDamageFlash` is 1 on the step a blow lands and decays to
0 over 0.35 s, another OpenSky number because no record states one.

## Reaction clips

An NPC plays one clip at a time, which is all `ActorAnimationPlayback` supported
before this item; it now takes a bounded override and returns to idle when the
override expires. `ActorAnimationClipLoader` decodes one, cached per skeleton and
kind.

| Reaction | Clip |
| --- | --- |
| attack | `meshes\actors\character\animations\h2h_attackright.hkx` |
| stagger | `meshes\actors\character\animations\1hm_staggerbacksmall.hkx` |
| hit reaction | `meshes\actors\character\animations\h2h_recoilright.hkx` |

Every path is a file name the vanilla behavior graphs themselves reference,
quoted from the census. Two things about that listing look inconsistent and are
not: the idle locomotion clips are gendered (`animations\male\mt_idle.hkx`) while
the combat clips are not, and **there is no unarmed stagger clip** — the census
carries `h2h_attackleft`, `h2h_attackright`, `h2h_recoilleft`, `h2h_recoilright`
and `h2h_recoiltimed`, but every `staggerback` variant is prefixed by a weapon
class. The one-handed small stagger is therefore what an unarmed stand-in plays.
All of these ride the same character rig, so the clip binds. It is a
substitution, and it is written down rather than silently made.

## Transient caps

Four populations grow while a fight runs and none shrinks on its own. Left alone,
a long session in one room ends with a thousand of each and the milestone's frame
budget stops meaning anything.

| Population | Ceiling | Trim order | What a trim costs |
| --- | --- | --- | --- |
| Arrows in flight | 12 | oldest first | Recorded `.cancelled` in the trace |
| Arrows stuck in the world | 32 | oldest first | Pulled back out |
| Corpses simulating | 8 | oldest first | Stops stepping, keeps its resting transform |
| Dynamic bodies awake | 64 | ascending `ReferenceKey` | Sleeps where it stands |

The numbers are OpenSky's. Vanilla's own caps live in its code rather than in any
record this engine reads, and no open source states them, so each is picked from
what the engine can carry at frame rate — the 15.2 clutter stress and the 15.6
repeated-collapse stress are the measurements behind them.

Trim order differs per population because only two of the three registries know
what "oldest" means. Projectiles and ragdolls are appended to in spawn order;
dynamic bodies are placed by their cell build and carry no spawn time, so the
awake cap sleeps them in the registry's own `ReferenceKey` order. Nothing here
deletes what a player is looking at: **the cap costs motion, not position.**

## Combat music

The seam [music](/engine/music.md) has been holding open since M9. `MusicState`
gains a `combat` case, and unlike the other three it is not derived from the
streamer's context at all — combat is a game-system state, so
`WorldMusicDirector.setCombatActive(_:)` selects a MUSC directly and the
precedence chain below it is untouched.

* **Entering combat** picks the first MUSC whose editor id starts with
  `MUSCombat` (case-insensitive), by FormID so the choice is the same on every
  run, and remembers the selection it interrupted.
* **Leaving combat** restores exactly that selection rather than re-resolving, so
  a fight that started in a town ends back in the town's playlist even if the
  streamer never published a context in between.
* **A cell crossed mid-fight** updates what leaving combat will return to instead
  of interrupting the fight's music.
* **A load order with no combat playlist** leaves the music where it was and says
  why. Nothing to select is not a reason to go silent mid-fight.

The `MUSCombat` prefix is a naming convention, not data — the same limit the
`town` state carries.

## Persistence

Hostility travels in its own additive save chunk, `CBTS`, for the reason `AVAL`
and `DETH` have their own: a component kind inside `RDLT` is versioned by
`formatVersion`, so putting it there would make an older build refuse every save
containing a fight instead of loading the rest of the world. A session in which
nothing was provoked writes no chunk at all. See
[the OpenSky save container](/formats/opensky-save.md).

An unknown hostility byte decodes as neutral rather than throwing: a future third
regard should load with that actor calm, not refuse the file.

`CombatLoopRuntime.prepareForPersistence()` runs on both sides of a save and
drops what a reload cannot reproduce — arrows in the air, corpses still falling,
the opponent's attack phase, the damage flash. What survives is what a component
carries: hostility, actor values, death. So a fight saved mid-swing reloads as a
fight, with the swing itself gone.

## Measured cost

`CombatLoopRealDataTests.theLoopStepStaysInsideItsBudgetWithACrowd()` runs the
loop over the install's own combat GMSTs with 32 resident actors — more than a
room holds, so the number is a ceiling rather than a typical case — and measures
one fixed step.

| Measurement | Value |
| --- | --- |
| Per fixed step, 32 actors | 0.0380 ms (2026-08-08, local install) |
| Budget | 0.1 ms |

The budget is an OpenSky number chosen the way the 15.2 step budget was: the loop
runs beside physics, animation and the Papyrus VM on the same fixed step, and a
tenth of a millisecond leaves the frame to the systems that draw. It is
deliberately generous — the loop derives a state over a small array and advances
one clock — so a regression that trips it is a real one.

The same suite pins the two claims a synthetic test cannot make: the vanilla
player graph declares `recoilStart`, `recoilStop`, `IsRecoiling` and
`recoilMagnitude`, and all three reaction clips decode against a real character
skeleton — including the substituted one-handed stagger, which is what proves the
substitution binds to the same rig rather than merely naming a plausible path.

## Panel seam

`CombatLoopControlProviding` (`opensky/Engine/CombatLoopControlProviding.swift`),
conformed by `GameViewControllerCombatPanel.swift`: one `Equatable` snapshot out,
plain actions in, matching every other panel bridge.

It carries the hostility toggle, the combat-state and current-target readouts, the
dev-target spawn and reset controls, the opponent's phase and counts, the
incoming-hit trace, the damage-flash value, and the live transient counts against
their ceilings. The readout lines are formatted by `CombatLoopReadout` in the
engine target, where a unit test can reach them without a window.

The `World > Combat & Physics` destination that reads this ships with the M15
acceptance gate (item 15.9), on the same reading items 15.3 to 15.6 made for
their own seams.

## Limits

Everything below is a known gap with a home, not an oversight:

* **No AI.** Perception, packages, pathing, factions and crime are M16.
* **The opponent does not move.** M16, with NPC behavior-graph locomotion.
* **NPCs have no behavior graph**, so a reaction raised on one answers false and
  the trace records that it did not play.
* **NPCs never block.** Only the player has a guard to raise, so
  `combatBlock(of:)` answers for the player alone.
* **One opponent.** The caps allow more and nothing forbids it, but only one dev
  target is designated at a time.
* **No power attacks and no bashing.** The census names both; they are M18's
  alongside perks and enchantments.

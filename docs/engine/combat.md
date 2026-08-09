---
type: Subsystem
title: Combat loop
description: Hostility, derived combat state, the per-actor combat behavior machine that
  approaches, attacks, blocks, flees, searches and gives up, hit reactions in both
  directions, transient caps, and the combat-music edge.
tags: [engine, combat, hostility, combat-ai, npc, music, persistence]
timestamp: 2026-08-09T00:00:00Z
---

# Combat loop

Roadmap items 15.7 (issue #374) and 16.7 (issue #424). Items 15.3 to 15.6 built
the pieces of a fight — values that can be taken off, a swing that takes them, an
arrow that flies, a corpse that falls and can be looted. Item 15.7 made a loop of
them around a stand-in opponent that was honestly a clock. Item 16.7 deleted the
clock and put a mind in its place. This page is that decision layer.

Impl: `opensky/Engine/Combat/CombatLoop*.swift`,
`opensky/Engine/Combat/CombatBehavior*.swift`,
`opensky/Engine/Combat/CombatTransientLimits.swift`,
`opensky/Engine/Actors/ActorCombatComponent.swift`, plus
`opensky/App/GameViewControllerCombat.swift` and its satellites.

The pieces it ties together: [melee combat](/engine/melee-combat.md),
[archery and projectiles](/engine/archery.md),
[death and ragdoll](/engine/ragdoll.md), [actor values](/engine/actor-values.md),
[detection](/engine/detection.md), [navigation](/engine/navigation.md),
[package schedules](/engine/package-schedules.md),
[dynamic rigid bodies](/engine/dynamic-bodies.md), [music](/engine/music.md).

## Contents

* [The mind that replaced the clock](#the-mind-that-replaced-the-clock)
* [Hostility](#hostility)
* [Entering a fight](#entering-a-fight)
* [Combat state is derived](#combat-state-is-derived)
* [The behavior machine](#the-behavior-machine)
* [The numbers, all of them ours](#the-numbers-all-of-them-ours)
* [Blocking, both ways](#blocking-both-ways)
* [Breaking off](#breaking-off)
* [Losing the player, searching, giving up](#losing-the-player-searching-giving-up)
* [How many fight at once](#how-many-fight-at-once)
* [Starting and stopping a fight from a script](#starting-and-stopping-a-fight-from-a-script)
* [Reactions in both directions](#reactions-in-both-directions)
* [Reaction clips](#reaction-clips)
* [Script events from a fight](#script-events-from-a-fight)
* [Transient caps](#transient-caps)
* [Combat music](#combat-music)
* [Measured cost](#measured-cost)
* [Persistence](#persistence)
* [Panel seam](#panel-seam)
* [Verification surface](#verification-surface)
* [Limits](#limits)

## The mind that replaced the clock

Through M15 the opponent was a **clock**, and the code said so at length. It
attacked on a fixed interval, from wherever it was standing, at whatever was in
front of it. It did not chase, it did not choose, and it did not give up. What it
*did* do was go through the shipping paths — the 15.4 hit volume, the 15.4 damage
formula, the 15.3 actor-value store — so everything downstream of "an opponent
hit the player" was already the real thing.

Item 16.7 collected the debt. `DevTargetDriver` and `CombatLoopRuntimeTarget` are
deleted; `CombatBehaviorMachine` decides instead, one machine per actor. What it
can now do that the clock could not:

| Capability | Reached through |
| --- | --- |
| Notice the player and start the fight unhit | [detection](/engine/detection.md) (16.6) |
| Walk to weapon range and chase a retreating player | [navigation](/engine/navigation.md) (16.4) |
| Raise a guard, so the player's hit is blocked | the 15.4 damage formula, unchanged |
| Break off at low health and run along a path | 16.4 again, away from the target |
| Hunt for a player who broke line of sight | 16.6's remembered investigate position |
| Give up and go back to work | [package schedules](/engine/package-schedules.md) (16.5) |

Everything the clock did through the shipping paths is still done through them.
The blow, the block, the stagger, the death and the ragdoll are the same code;
what changed is who decides to swing, and when, and from where.

## Hostility

One enum per actor, `ActorHostility`, stored as the `ActorCombatState` component
and therefore journalled, dirty-counted and saved like every other world-state
write ([runtime state](/engine/runtime-state.md)).

| Case | Meaning |
| --- | --- |
| `neutral` | The actor has no quarrel with the player. Every actor starts here. |
| `hostile` | The actor has a quarrel with the player. |

There is deliberately no `dead` case: death is `ActorDeathState.isDead`, and a
second spelling of the same fact is a second thing to keep in agreement.

Hostility is entered exactly three ways:

1. **The player hurt it.** `CombatLoopRuntime.provoke(_:)` is called from the
   melee hit path and from the projectile impact path, so a swing and an arrow
   anger a target identically. It is idempotent, so each caller can call it
   without checking first.
2. **The panel toggle.** `CombatLoopControlProviding.selectedActorIsHostile`.
3. **A script.** `StartCombat`, which writes hostility on its way through
   (issue #424).

There is still no aggro radius, no faction relation, no disposition arithmetic
and no crime. Those need factions and a relationship store, which 16.7
deliberately did not add.

## Entering a fight

Hostility is how an actor *feels*. Starting to fight is a separate edge, and
16.7 widened it by exactly one source.

| Entry | Since | What it does |
| --- | --- | --- |
| The player struck it | 15.7 | Provokes it and staggers it; the machine is engaged for the step it takes to turn around |
| A script called `StartCombat` | 16.7 | Engages it at once, without waiting for it to perceive anything |
| **It perceived the player** | **16.7** | A hostile actor whose 16.6 detection level reaches `detected` starts fighting, unhit |

That third row is the whole of scope point 5. It is why the panel's hostility
checkbox no longer starts a fight on its own: an actor made hostile from the
sidebar stands there until it notices the player, which is what a bandit in a
cave does.

Being *suspicious* is not enough. A detection level between the two thresholds
means the observer has something worth investigating, not a target — and
committing to a fight on a half-seen shape would make every guard in Whiterun
attack a passing shadow.

## Combat state is derived

"Is the player in combat" is **not stored**. It is derived every fixed step from
the resident actor list: in combat means *some resident actor is engaged* —
fighting the player or searching for them — and the current target is the nearest
hostile living actor, ties broken on the lower `ReferenceKey`.

Item 16.7 moved that edge from "somebody is angry" to "somebody is fighting".
While the opponent was a clock the two were the same thing, because a hostile
actor had nothing else it could be doing. They are not the same now: an actor
that has not noticed the player, and one that searched and gave up and walked
back to its schedule, are both hostile and both out of the fight. Deriving from
engagement is what makes the combat music stop when the fight ends rather than
when the actor is finally killed or calmed.

The *target* is deliberately still the nearest hostile, engaged or not: "who am I
fighting" from the player's side is answered by turning to face somebody, and an
actor that is hostile but has not noticed the player is still the thing the
player is about to fight.

Deriving it is what keeps it honest. A target that died, a cell that unloaded,
and a hostility cleared from the panel all change the answer on the next step
with nothing to invalidate. A stored flag would have to be cleared from each of
those places, and the one that was forgotten would leave the player permanently
in combat with a corpse.

Nearest rather than most-recently-hit, because both consumers — the music edge
and the combat-target condition run-on — want "who am I fighting", and a player
who turned to face a second attacker has answered that by turning.

## The behavior machine

`CombatBehaviorMachine` is a pure value advanced by one fixed step at a time, so
a run at 60 frames a second and a run at 144 produce the same fight. One machine
per actor, seeded from that actor's own `ReferenceKey`.

| Phase | Leaves it when | What it asks the world for |
| --- | --- | --- |
| `idle` | it perceives the target, or a script or a blow puts it in the fight | nothing |
| `approaching` | it is inside its own weapon reach, less the slack | a path to the target, re-issued on the command interval |
| `spacing` | the attack interval is up | a stop |
| `blocking` | the block duration is up | a stop |
| `windup` | the windup duration is up | nothing |
| `contact` | one step | nothing — the hit volume runs here, once |
| `recovery` | the recovery duration is up | nothing |
| `staggered` | the stagger duration is up | nothing |
| `fleeing` | it is further from the target than the break distance | a path away from the target |
| `searching` | it perceives the target again, or the search time is up | a path to the remembered position |
| `disengaged` | it perceives the target again | a stop, and a package re-selection |

The attack phases mirror the player's own (`MeleeCombatState`) on purpose, so the
two sides of a fight are legible against each other, and a stagger takes the
attack away exactly as the graph's own stagger transition does for the player.

**The machine asks for movement; it never performs it.** It emits a
`CombatMovementCommand` and the runtime hands it to 16.4's `MoveToPointControl`,
which owns the capsule, the navmesh path, the stuck recovery and the persistence.
A combat layer that wrote positions would be a second movement authority that
disagreed with the first. This is why fleeing is "ask for a point away from the
target" rather than "walk backwards", and why a point no navmesh reaches is a
refused request the machine retries rather than a slide through a wall.

Where a decision is not determined by its inputs — the block roll and the flee
angle — the draw comes from a `ConditionRandom` seeded per actor from that
actor's `ReferenceKey`, the same splitmix generator `GetRandomPercent` uses. The
seed is folded from the key's own spelling rather than from `hashValue`, because
Swift seeds `String` hashing per process and a `hashValue` seed would make two
runs of the same fight differ.

## The numbers, all of them ours

Every constant the machine runs on is **OpenSky's, not Bethesda's**. No record
states an attack cadence, a block probability, a flee threshold or a search
duration; vanilla's live in the combat-AI binary. They are chosen in the open, in
`CombatBehaviorSettings`, with the reason written beside each.

| Setting | Value | Why that one |
| --- | --- | --- |
| `attackIntervalSeconds` | 1.6 s | Slow enough to block, draw a bow, and watch what happened between blows |
| `windupSeconds` | 0.45 s | Roughly where the vanilla one-handed attack clip puts its `HitFrame` |
| `recoverySeconds` | 0.35 s | Follow-through during which no new attack starts |
| `staggerSeconds` | 0.7 s | How long a hit holds the attack away |
| `blockChance` | 0.35 | Roughly one gap in three: often enough to learn, rare enough that attacking still ends fights |
| `blockSeconds` | 1.6 s | Deliberately equal to the interval, so blocking replaces the wait rather than shortening or lengthening the cadence |
| `reachSlack` | 24 u | Larger than the mover's 12-unit waypoint tolerance, so a target at the reach boundary does not oscillate |
| `commandIntervalSeconds` | 0.5 s | Sixteen path queries a second at the engagement cap, inside 16.4's budget |
| `fleeHealthFraction` | 0.2 | Visible before the kill, not triggered by the first blow |
| `fleeDistance` | 1400 u | About twenty metres per flee request |
| `fleeBreakDistance` | 1800 u | Larger than one flee hop, so a path the navmesh cut short is retried |
| `searchSeconds` | 8 s | Long enough to hear it end, short enough not to pin a hidden player |

## Blocking, both ways

`CombatLoopWorld.combatBlock(of:)` used to answer for the player alone, because
only the player had a guard to raise. It now answers for everybody: the player
from the melee runtime's own graph state, every other actor from its machine's
`blocking` phase. A blocked hit in either direction goes through the same pinned
15.4 damage formula, and neither side has a damage path of its own.

An NPC's block always reports `.weapon`, never `.shield`. Telling the two apart
needs the equipment resolution this engine does not do for an NPC's *combat*
(only for drawing it), and reporting `.shield` on a guess would move the
reduction to a different pinned constant on no evidence. Stated, not hidden.

The roll happens once per attack cycle, on entering the gap, rather than once per
step — so `blockChance` means what it says, per attack, and not per sixtieth of
a second.

## Breaking off

At or below `fleeHealthFraction` of its maximum health an actor stops fighting
and runs: it asks 16.4 for a point `fleeDistance` away along the line from the
target through itself, turned by a seeded angle so a straight line into whatever
is behind it is not the only thing tried and two actors fleeing one swing
scatter. It keeps asking on the command interval until it is further from the
target than `fleeBreakDistance`, and then leaves the fight.

A fleeing actor is still **engaged**, which is what keeps the combat music
playing while it runs and stops as soon as it is away. Health recovering above
the threshold does not bring it back: nothing in this engine heals an NPC
mid-fight, and an actor that turned and ran and then turned around again would be
a decision the player cannot read. An actor still under the threshold will not
start a fight at all, which is what stops the one it just ran from restarting the
moment it looks back.

## Losing the player, searching, giving up

When 16.6 detection stops reporting `detected`, the actor goes to the position
detection remembered — the investigate position, which that page drops as soon as
the level decays to nothing, so a stale position can never be walked to — and
looks around for `searchSeconds`.

* While searching, `GetCombatState` returns **2**. That is the third documented
  return, and 16.7 is what makes it reachable; see
  [conditions](/formats/conditions.md).
* A searching actor is still engaged, so the player is still in combat and the
  music still plays. That is the searching seam the music runtime has held open.
* Perceiving the target again mid-search resumes the chase.
* The search timing out ends the pursuit: the actor stops, and its 16.5 package
  is re-selected immediately.
* Losing the target with *nothing* remembered gives up outright rather than
  searching where the actor happens to be standing.

Giving up leaves **hostility untouched**. The actor still has its quarrel, so
walking back into its view starts the fight again — with a second entry in its
own fight count, which the panel shows.

Resuming a package is a fresh `forceReevaluate`, not a resume of a saved
procedure: the world has moved on by however long the fight lasted, and the
package the schedule names *now* is the one the actor should be doing.

## How many fight at once

`CombatLoopRuntime.maximumEngagedActors` is deliberately
`NPCMovementRuntime.maximumSimultaneousMovers` — eight. Every engaged actor asks
the mover for a path, so a ninth fighter would be one whose approach silently
never started.

Past the cap the nearest actors win and `crowdedOutCount` records how many did
not, because a silent truncation would read as "nobody else was fighting". The
panel prints the number.

The player's own current target is unchanged by any of this: it is still the
nearest hostile living actor, engaged or not.

## Starting and stopping a fight from a script

`StartCombat(Actor akTarget)` and `StopCombat()` are installed as `Actor` natives
(see [the Papyrus VM](/engine/papyrus-vm.md)). Both route through
`CombatLoopRuntime` rather than writing `ActorCombatState` directly, so a
script's fight enters by the same door the player's does: hostility through the
world-state store, the same machine engaged, and the same hand-back to the
package when it stops.

* `StartCombat` engages the actor at once, without waiting for it to perceive
  anything, and records the target the script named.
* Only the player is accepted as that target. Actor-versus-actor combat is out of
  scope — `ActorHostility` has two cases and both are about the player — so a
  script naming anybody else takes a tallied failure that says why, rather than a
  fight that silently does not happen.
* `StopCombat` ends the fight and leaves stored hostility alone. The wiki's
  `StopCombat` stops the fighting; changing how somebody *feels* is a different
  function, and this engine has no relationship store for it.

That last point has a consequence worth stating: an actor stopped mid-fight is
still hostile and still standing in front of the player, so the next step
perceives them and the fight starts again. That is the same reason a vanilla
script that means it also changes the relationship rank. Making it stick here
means clearing hostility as well, which the panel checkbox does and no native
does.

## Reactions in both directions

The target staggers, the player recoils.

* **Target staggered.** A landed player hit calls
  `CombatLoopRuntime.noteStagger(of:)`, which interrupts that actor's machine and
  plays the stagger clip. An actor that was not fighting at all is in the fight
  afterwards: being struck is being told where somebody is, and that is the
  *existing* combat entry rather than a second perception rule. The 15.4 path
  also raises `staggerStart` on the target's graph, which answers false
  because NPCs have none — the readout records that rather
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

## Script events from a fight

Issue #375 (roadmap item 15.8) gives a fight its scripting surface. Three seams —
`MeleeCombatWorld`, `ProjectileWorld` and `CombatLoopWorld` — all refine
`ScriptHitReporting`, whose single `reportScriptHit(_:)` method carries a
do-nothing default so every acceptance fake keeps compiling and a session with no
script VM honestly reports zero queued events.

`ScriptHitEvent` carries exactly the seven `OnHit` parameters the Creation Kit
documents, in its vocabulary rather than the melee runtime's, so the world
runtime turns it straight into event arguments. Each runtime reports *after*
applying the damage, so a script that reads the target's health inside its
handler sees the blow that caused the event. Three of the seven are always false:
power attacks, sneak attacks and bashing do not exist in this engine yet.

Deaths take the same shape from the other end.
`RagdollWorldSeam.queueActorDeathEvents(for:killer:)` is called from inside
`RagdollRuntime`'s death latch, which is what makes `OnDying` and `OnDeath` fire
exactly once whether the corpse was made by a sword, an arrow, a sidebar control
or a script's `Kill`. `RagdollRuntime.deathEventsQueued` counts them beside the
graph-driven and fallback death counts, so "the scripts were told" and "the graph
drove it" are two readable numbers rather than one assumption.

The condition side of the same state is
[conditions](/formats/conditions.md): `GetCombatState`, `GetDead`, `IsWeaponOut`
and the two actor-value functions read a snapshot of exactly this, and CTDA
run-on type 3 resolves against the fight described in
[combat state is derived](#combat-state-is-derived) — the player fights the
nearest hostile living actor and every *engaged* living actor fights the player.
`GetCombatState` reads the behavior phase rather than stored hostility, so it
returns 0 for an actor that hates the player and has not noticed them, 1 while it
is fighting, and 2 while it is searching.

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
| Per fixed step, 32 actors, one fight | 0.0334 ms (2026-08-09, local install) |
| Per fixed step, 32 clocks (M15, for comparison) | 0.0380 ms (2026-08-08) |
| Budget | 0.1 ms |

The mind costs less per step than the clock did, which reads oddly until the
engagement cap is remembered: 32 hostile actors produce 8 machines and 24 that
are counted and skipped, where 15.7 derived a state over all 32 and stepped one
clock. The cap is what keeps the number flat as a room fills.

The budget is an OpenSky number chosen the way the 15.2 step budget was: the loop
runs beside physics, animation and the Papyrus VM on the same fixed step, and a
tenth of a millisecond leaves the frame to the systems that draw. It is
deliberately generous — the loop derives a state over a small array and advances
one clock — so a regression that trips it is a real one.

`CombatLoopRealDataTests.aWhiterunHostileRunsTheWholeLoopAgainstThePlayer()` is
item 16.7's own acceptance: a real `GuardWhiterun*` ACHR, made hostile, running
the whole loop against a player walking in across the real city's collision and
then hiding, offscreen and with no mover attached.

```text
GuardWhiterunImperialPostNight1 (skyrim.esm:03704B) at (26884.4, 1744.9, -1425.7)
phases idle -> approaching -> blocking -> windup -> contact -> recovery
       -> spacing -> windup -> searching -> disengaged
2600 fixed steps, 0.0334 ms per step offscreen
10.0 damage taken, 9 path requests refused
```

The refused path requests are the honest half: that harness has no 16.4 mover
under it, so the guard fought from where the level designer put it while the
player walked in, and the requests it made are counted rather than hidden.

The same suite pins the two claims a synthetic test cannot make: the vanilla
player graph declares `recoilStart`, `recoilStop`, `IsRecoiling` and
`recoilMagnitude`, and all three reaction clips decode against a real character
skeleton — including the substituted one-handed stagger, which is what proves the
substitution binds to the same rig rather than merely naming a plausible path.

## Panel seam

`CombatLoopControlProviding` (`opensky/Engine/CombatLoopControlProviding.swift`),
conformed by `GameViewControllerCombatPanel.swift`: one `Equatable` snapshot out,
plain actions in, matching every other panel bridge.

It carries the hostility toggle, the combat-state and current-target readouts, one
`CombatActorReadout` per actor with a behavior machine — name, phase, awareness,
distance, health fraction, and the attack, contact, block and search counts — the
number the engagement cap refused, the incoming-hit trace, the damage-flash value,
and the live transient counts against their ceilings. The readout lines are
formatted by `CombatLoopReadout` in the engine target, where a unit test can reach
them without a window.

Item 16.7 removed `spawnCombatDevTarget()` and `resetCombatDevTarget()` from this
protocol along with the clock they drove. There is nothing to spawn: making an
actor hostile and letting it notice the player *is* the fight.

## Verification surface

`World > Combat & Physics` (`Destination-combatPhysics`) is the M15 milestone's
verification surface, and the gate's own record. Six sections, in the order a
fight happens in: what the actors are worth, what the player swings, what the
player shoots, what dies, who is angry, and what the physics is carrying while
all of it runs. Melee, Archery and Death & Ragdoll moved here from
`World > Player & Locomotion` with item 15.9, which is what items 15.4, 15.5 and
15.6 each said would decide their home once the combat surface outgrew that
panel.

The Combat Loop section is this page's own:

| Control | Id | Does |
| --- | --- | --- |
| Selected actor is hostile | `CombatHostilityControl` | writes the nearest resident actor's regard for the player; clearing it ends any fight it is in and hands it back to its package |
| Clear hit trace | `CombatClearTraceControl` | empties the incoming trace and its count |
| Readout | `CombatLoopStatsLabel` | combat state and target, one line per fighting actor (phase, awareness, distance, health, counts), hostility, hits taken, live transients against their ceilings |

Hostility alone no longer starts a fight — the actor has to notice the player
first, which is [detection](/engine/detection.md)'s job and is inspectable under
`World > Perception`. That is the shipping path rather than a developer shortcut
into it, which is why the shortcut is gone.

The other five sections are documented on their own pages:
[actor values](/engine/actor-values.md), [melee combat](/engine/melee-combat.md),
[archery](/engine/archery.md), [ragdoll](/engine/ragdoll.md) and
[dynamic bodies](/engine/dynamic-bodies.md).

A frozen physics simulation is the destination's one overridden-ness — the
sidebar dot lights for it and "Reset all" releases it. A damaged actor, an angry
opponent, a corpse on the floor and a shoved crate are world state a user made on
purpose, so none of them lights the dot and no reset undoes them.

### The M15 acceptance record

The record `docs/tools/sidebar-acceptance.md` requires, in the shape it fixes:

```text
Milestone: M15
Sidebar path: World > Combat & Physics > Actor Values, > Melee, > Archery,
  > Death & Ragdoll, > Combat Loop, > Physics
Destination id: Destination-combatPhysics
Controls exercised: ActorValueTargetControl, ActorValueKindControl,
  ActorValueAmountControl, ActorValueDamageControl, MeleeWeaponDrawnControl,
  MeleeAttackControl, ArcherySpawnControl, RagdollTriggerControl,
  CombatHostilityControl, CombatClearTraceControl, PhysicsFreezeControl,
  PhysicsResetControl
Readout: CombatLoopStatsLabel (plus CombatActorValuesStatsLabel,
  CombatMeleeStatsLabel, CombatArcheryStatsLabel, CombatRagdollStatsLabel,
  CombatPhysicsStatsLabel)
Deterministic tests: M15AcceptanceTests, M15AcceptancePanelTests,
  M15AcceptanceBudgetTests, M15AcceptanceRealDataTests (env-gated),
  M15AcceptanceRenderTests (env-gated and device-gated), CombatPhysicsPanelTests,
  DestinationRegistryTests, AppSidebarModelTests
Local A/B (optional, never committed): logs/m15-weapon-drawn.png,
  logs/m15-mid-swing.png
```

Item 16.7 edited that record rather than leaving it standing: the two dev-target
controls it named no longer exist, so the record now names the two the same
section actually exposes. The M15 gate still passes — the fight it drives is the
same fight, with a mind rather than a clock swinging.

## Limits

Everything below is a known gap with a home, not an oversight:

* **No power attacks, bashing or dodging.** M18, with perks. The census names
  all three.
* **No magic.** An actor never casts. M18 and later, with the magic-effect layer.
* **No factions, crime, group tactics or morale.** `ActorHostility` still has two
  cases and both are about the player, so there is no relationship rank to read,
  no crime gold to accrue, and no coordination between two actors fighting the
  same player beyond both of them fighting it.
* **No ranged-weapon AI.** An actor closes to melee reach whatever it is
  holding. The archery runtime is the player's alone; giving an actor a bow is a
  follow-up issue rather than something this item half-did.
* **Every actor swings unarmed.** `combatWeapon(of:)` answers
  `MeleeWeaponProfile.unarmed` for everybody: item 15.5 equips the *player* from
  the inventory layer, and an NPC's equipment is resolved for *drawing* only
  (`ActorVisualResolutionEquipment`). Reporting the model's sword as a swing
  profile would be inventing a damage number from a mesh.
* **An NPC's block is always `.weapon`, never `.shield`**, for the same missing
  resolution. The reduction therefore always uses the weapon constants.
* **NPCs have no behavior graph**, so a graph event raised on one answers false
  and the trace records that it did not play. NPC reactions are single-clip
  playback (`playCombatClip(_:on:)`), which is what
  [actor animation](/engine/actor-animation.md) supports.
* **Eight actors fight at once.** The cap is the mover's, the nearest win, and
  what was refused is counted rather than dropped silently.
* **`StopCombat` alone does not keep an actor calm** while it is still hostile
  and can still see the player, for the reason above. There is no
  `SetRelationshipRank` to pair it with.
* **`StartCombat` accepts only the player as a target.** Actor-versus-actor
  combat is not simulated, and a script naming a third party takes a tallied
  failure that says so.
* **`OnHit` never reports a power, sneak or bash attack**, and its `akSource`
  and `akProjectile` handles name base records that resolve to no script
  instance: a handler may compare and log them but cannot call a method on one.
* **Combat perception is one-directional.** 16.6 tracks observers against the
  player only, so an actor cannot lose a target that is not the player, and the
  search state is about the player alone.

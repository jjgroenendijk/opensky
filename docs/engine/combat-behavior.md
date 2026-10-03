---
type: Subsystem
title: Combat behavior
description: The per-actor combat machine - its phases, how it chooses between a swing and a spell,
  its settings and why each was chosen, blocking, fleeing, searching and giving up, hit reactions
  in both directions, reaction clips, and its cost per step.
tags: [engine, combat, combat-ai, npc, magic]
---

# Combat behavior

Each engaged actor runs one combat machine. It decides when to swing, block, cast, run, and search.
Who fights at all is on the [combat loop](/engine/combat.md) page.

The machine does not own a damage path. The blow, the block, the stagger, the death, and the ragdoll
go through the same code the player's fight uses ([melee damage](/engine/melee-damage.md)). The
machine only decides who swings, when, and from where.

## Phases

The machine is a pure value, moved one fixed step at a time. So a run at 60 frames per second and a
run at 144 give the same fight. Each actor has its own machine.

| Phase | Leaves when | Asks the world for |
| --- | --- | --- |
| `idle` | It perceives the target, or a script or a blow puts it in the fight | Nothing |
| `approaching` | It is inside its own weapon reach, minus the slack | A path to the target, sent again each command interval |
| `spacing` | The attack interval is over | A stop |
| `blocking` | The block time is over | A stop |
| `casting` | The spell's charge time is over, plus the hold for a held spell | A stop, and a cast started and released |
| `windup` | The windup time is over | Nothing |
| `contact` | One step | Nothing. The hit volume runs here, once |
| `recovery` | The recovery time is over | Nothing |
| `staggered` | The stagger time is over | Nothing |
| `fleeing` | It is further from the target than the break distance | A path away from the target |
| `searching` | It sees the target again, or the search time is over | A path to the remembered position |
| `disengaged` | It sees the target again | A stop, and a new package choice |

The attack phases match the player's own melee phases on purpose, so both sides of a fight can be
read against each other. A stagger takes the attack away, as the graph's stagger transition does for
the player.

The machine asks for movement and never moves anything. Its command goes to the navigation mover,
which owns the capsule, the navmesh path, stuck recovery, and saving
([navigation](/engine/navigation.md)). A combat layer that wrote positions would be a second source
of movement that disagreed with the first. So fleeing is "ask for a point away from the target", not
"walk backwards". A point no navmesh reaches is a refused request the machine tries again, not a
slide through a wall.

The block roll and the flee angle are random. They come from a generator seeded per actor from its
`ReferenceKey`, the same splitmix generator `GetRandomPercent` uses. The seed is built from the key's
own text, not from `hashValue`: Swift seeds `String` hashing per process, so a `hashValue` seed
would make two runs of the same fight differ.

## Swing or spell

Casting is a phase, not a kind of attack. A swing is timed by the machine and lands at the contact
step. A cast is timed by the `SPIT` charge time and lands wherever its delivery takes it
([magic](/engine/magic.md)). They share only when they are chosen:

- An actor that cannot reach its target with a weapon casts whenever it can afford a spell that
  reaches. Otherwise it would walk toward someone while holding something it could have thrown.
- An actor inside weapon reach casts with probability `castChance`, and swings otherwise, from the
  same seeded generator as the block roll.
- The spell is the most expensive one it can both afford and reach with. Ties go by spell order.
  Cost as a measure of strength is a choice: no record says how a caster ranks its spells. This
  spends a full bar on the strongest spell and falls down the list as the bar drains.
- A caster that can afford nothing goes back to closing in and swinging, so a mage out of magicka
  stays in the fight.

A charge is dropped in exactly one place: the step that left the casting phase without releasing.
So fleeing, losing the target, giving up, a stagger, and death all clean up a cast none of them
started.

## Settings

Every value here is OpenSky's. No record states an attack rhythm, a block chance, a flee threshold,
a search time, or how often a caster prefers a spell. Vanilla keeps these in the combat AI code.
So they are chosen in the open, with a reason each. An actor's
[combat style](#combat-style) then scales some of them.

| Setting | Value | Why this value |
| --- | --- | --- |
| Attack interval | 1.6 s | Slow enough to block, draw a bow, and see what happened between blows |
| Windup | 0.45 s | About where the vanilla one-handed attack clip puts its `HitFrame` |
| Recovery | 0.35 s | Follow-through with no new attack |
| Stagger | 0.7 s | How long a hit holds the attack away |
| Block chance | 0.35 | About one gap in three: often enough to learn, rare enough that attacks still end fights |
| Block time | 1.6 s | Equal to the interval, so blocking replaces the wait without changing the rhythm |
| Reach slack | 24 units | More than the mover's 12-unit waypoint tolerance, so a target at the edge of reach does not cause back and forth |
| Command interval | 0.5 s | Sixteen path queries a second at the engagement limit, inside the navigation budget |
| Flee health | 0.2 of maximum | Visible before the kill, not set off by the first blow |
| Flee distance | 1,400 units | About 20 m per flee request |
| Flee break distance | 1,800 units | More than one flee hop, so a path the navmesh cut short is tried again |
| Search time | 8 s | Long enough to hear it end, short enough not to pin a hidden player |
| Cast chance | 0.5 | Even odds in weapon reach. A caster that never swings is pinned by an opponent who closes in. One that always swings never looks like a mage |
| Held spell time | 1.5 s | Two applications of a once-a-second effect: long enough to see a beam, short enough to decide again |

## Combat style

An actor's `CSTY` [combat style](/formats/combat-style.md) scales the settings above for that
actor. No source says how the game turns a style multiplier into behavior, so each mapping is
OpenSky's. Each one is monotonic, is clamped, and leaves the settings unchanged at 0.5, the
middle of the 0 to 1 range that vanilla styles use. Vanilla `DefaultCombatstyle` sets both
multipliers to 0.24, so an actor on it attacks less often and blocks less than the base.

| Setting | Scaled by | Rule | Clamp |
| --- | --- | --- | --- |
| Attack interval | Offensive multiplier | Base times 0.5 / offensive: twice the offense, half the wait | 0.5 to 2 times the base |
| Block time | Offensive multiplier | The same scale as the attack interval, so a block still replaces one gap | 0.5 to 2 times the base |
| Block chance | Defensive multiplier | Base times defensive / 0.5 | 0 to 0.9 |
| Cast chance | Melee and magic equipment score multipliers | Base times 2 times magic / (magic + melee); equal scores give the base | 0 to 0.9 |

A chance never reaches 1, so the other choice stays possible. A member a record leaves out,
or a value that is not finite or not positive, counts as the neutral value. An actor with no
style uses the settings unchanged. The `World > Combat Loop` readout shows the selected
actor's style and the derived numbers.

## Blocking

The block query answers for everyone. The player's comes from the melee runtime's graph state. Every
other actor's comes from its machine's `blocking` phase. A blocked hit in either direction uses the
same damage formula.

The block roll happens once per attack cycle, when the actor enters the gap, not once per step. So
the block chance means what it says: per attack, not per sixtieth of a second.

## Fleeing

At or below the flee health fraction, an actor stops fighting and runs. It asks for a point at the
flee distance along the line from the target through itself, turned by a seeded angle. So a straight
line into whatever is behind it is not the only try, and two actors fleeing one swing scatter. It
asks again each command interval until it is past the break distance, and then leaves the fight.

A fleeing actor is still engaged, so the combat music plays while it runs and stops when it is away.
Health rising above the threshold does not bring it back: nothing heals an NPC mid-fight, and an
actor that ran and then turned around again would be hard to read. An actor still under the
threshold does not start a fight at all, so the one it fled from does not restart the moment it
looks back.

## Searching and giving up

When [detection](/engine/detection.md) stops reporting `detected`, the actor goes to the position
detection remembered and looks around for the search time. Detection drops that position as soon as
the level decays to nothing, so a stale position is never walked to.

- While searching, `GetCombatState` returns 2 ([conditions](/formats/conditions.md)).
- A searching actor is still engaged, so the player is still in combat.
- Seeing the target again resumes the chase.
- When the search time ends, the actor stops and its package is chosen again at once.
- Losing the target with nothing remembered gives up at once, instead of searching where the actor
  stands.

Giving up leaves hostility as it is. Walking back into view starts the fight again, and the panel
counts a second fight. The package is a fresh choice, not a resumed one: the world moved on during
the fight, and the package the schedule names now is the right one.

## Hit reactions

- The target staggers. A landed player hit interrupts that actor's machine and plays the stagger
  clip. An actor that was not fighting joins the fight: being struck tells it where someone is. The
  hit also raises `staggerStart` on the target's graph, which returns false because NPCs have none.
  The trace records that.
- The player recoils. A landed opponent blow writes `recoilMagnitude` and then raises `recoilStart`
  on the player's graph, in that order, so the recoil reads this blow's number. The melee runtime
  uses the same write-then-raise order for a stagger.

`recoilStart`, `recoilStop`, `recoilLargeStart`, `IsRecoiling`, and `recoilMagnitude` all come from
the behavior census of the install: the third-person `0_master.hkx` declares all five.
`recoilLargeStart` is never raised. No open source states which magnitude chooses the heavier
reaction.

The HUD damage flash is a value, not a drawn effect: 1 on the step a blow lands, falling to 0 over
0.35 s. That time is OpenSky's.

## Reaction clips

An NPC plays one clip at a time. It can take a short override clip and go back to idle when it ends.

| Reaction | Clip |
| --- | --- |
| Attack | `meshes\actors\character\animations\h2h_attackright.hkx` |
| Stagger | `meshes\actors\character\animations\1hm_staggerbacksmall.hkx` |
| Hit reaction | `meshes\actors\character\animations\h2h_recoilright.hkx` |

Every path is a file the vanilla behavior graphs reference. Two things look odd and are not. The
idle clips are split by sex (`animations\male\mt_idle.hkx`) while the combat clips are not. And there
is no unarmed stagger clip: the census has `h2h_attackleft`, `h2h_attackright`, `h2h_recoilleft`,
`h2h_recoilright`, and `h2h_recoiltimed`, but every `staggerback` variant starts with a weapon class.
So an unarmed actor plays the one-handed small stagger. All of them use the same character rig, so
the clip binds. It is a substitution, written down here.

## Cost

The budget is 0.1 ms per fixed step. The loop runs beside physics, animation, and the Papyrus VM on
the same step, and a tenth of a millisecond leaves the frame to the systems that draw. With 32 actors
in loaded cells, more than a room holds, one step measures about a third of that. The engagement
limit keeps the cost flat as a room fills: 32 hostile actors give 8 machines, and the other 24 are
counted and skipped.

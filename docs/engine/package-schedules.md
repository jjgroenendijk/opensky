---
type: Subsystem
title: Actor package schedules
description: Ordered resident-actor package selection, bounded reevaluation, procedure
  machines, current-state inspection, and the intentional first AI-runtime limits.
tags: [engine, ai, actors, packages, schedules, navigation]
timestamp: 2026-08-09T00:00:00Z
---

# Actor package schedules

Issue #201 turns decoded [PACK records](/formats/packages.md) into deterministic current
activity for resident actors. The engine layer is UI-free; issue #203 consumes its readout
and force-reevaluation seams in the M16 acceptance panel.

## Selection and inheritance

`PackageStore` indexes PACK and NPC_ records once beside the other cell-build provider
indexes. `ActorTemplateResolver.resolvePackages(base:)` applies only the ACBS
`useAIPackages` flag: a local empty list stays authoritative unless that flag explicitly
delegates the whole ordered `PKID` stack to the template record.

For each registered resident actor, `ActorPackageRuntime` walks that stack in record order.
It selects the first package whose `PSDT` schedule matches and whose header `ConditionList`
evaluates true. A concrete package may follow a template chain; the concrete record remains
the schedule and condition owner, while the terminal template supplies the procedure kind.
Missing packages are skipped during selection. Direct resolution reports missing targets and
template cycles as typed `PackageResolveError` values.

## Reevaluation and inspection

Selection is event-driven. The next pass is the earlier of an exact daily schedule start or
end and a 15-game-minute maximum interval. The interval bounds calendar changes and mutable
condition inputs without polling every frame. A clock moving backwards also forces a pass.
The future panel can call `forceReevaluate` after a user mutation.

Each actor readout contains actor identity, base FormID, current package FormID and editor
ID, schedule, procedure kind, and last evaluation game time. A selection-change callback
fires only when the selected FormID changes.

`GetDisabled` reads one immutable `ReferenceEnableResolution`: a runtime Enable/Disable
component wins, otherwise the REFR or ACHR record-header initially-disabled flag is the
baseline. This makes Heimskr's condition flip honest without letting condition evaluation
reach into the main-actor world-state store.

## Procedure machines

`PackageProcedureMachine` is a deterministic, bounded state machine. It emits commands for
the existing movement and future animation adapters rather than owning either system.

| procedure | minimal behavior |
| --- | --- |
| travel | move to the resolved destination, then complete |
| wander | choose seeded points in a radius, pause one second, repeat |
| sandbox | choose seeded points in a radius, pause four seconds, repeat |
| sleep | move to the destination, then request a sleep loop |
| eat | move to the destination, then request an eat loop |

Movement failure ends a machine as failed. Unsupported template procedures also fail
explicitly. Wander points are uniform by area (`sqrt` radius sampling) and seeded through
the same deterministic random generator used by conditions. Synthetic acceptance sends the
travel command through the real resident navmesh pathfinder and pins all five state
transitions.

## Runtime boundaries

The app reconciles streamed ACHRs into the selector on the ordinary world-simulation tick.
Actors leaving residency are unregistered; actors entering it evaluate against the live
clock, quest/actor state, resident reference index, and immutable world-state enable
snapshot. Selection therefore runs in a real session now, while the procedure command
adapter and animation-event choice land with their visible consumer. Location and target
data are decoded, but aliases and linked references need their owning runtime scopes before
they can become world destinations.

The branch graph inside a template procedure is not interpreted, and only `GetDisabled`
was added to condition coverage. Unsupported conditions stay reason-tagged false. The
Whiterun pre-siege acceptance intentionally observes that behavior for Heimskr's jailed
package.

NPC trigger occupancy is not duplicated here. Issue #423 already made moving actor capsules
diff trigger-volume occupancy and dispatch the actor as `akActionRef`; package movement will
feed that same `MoveToPointControl` path.

## Evidence

Synthetic tests cover first-match priority, schedule edges and midnight wrap, a mutable
condition flip, actor/package template inheritance, missing/cyclic templates, bounded and
on-demand reevaluation, all five procedures, and travel over synthetic NAVM geometry.

The env-gated Skyrim.esm test follows 21 PACK records reachable from Ysolda, Belethor,
Hulda, and Heimskr. It pins the raw subrecord census and header-function tally, then selects
each actor at every integer hour of a full pre-siege day. Game data is read in place and no
record bytes or captures are written into the repository.

## Verification surface

`World > AI & Navigation > Package` (`Destination-aiNavigation`) shows the selected actor's
current package, its editor ID, its resolved procedure and its authored schedule, spelled as
a start time and a duration rather than as the row of signed bytes PSDT carries, in
`AIPackageStatsLabel`. Which actor it answers for comes from the destination's own Actor
section.

`AIPackageReevaluateControl` is the one control, and it is deliberately the only one.
Selection is driven by the game clock and by the conditions the stack carries, so a panel
that set a package directly would be showing a state the schedule never produced. The way to
watch the schedule decide is to scrub the clock under `World > Runtime State > Time` and
press Reevaluate, which runs `forceReevaluate(actor:clock:context:)` rather than waiting out
the fifteen-game-minute interval.

The acceptance record for item 16.5 is a row in
[the sidebar acceptance ledger](/tools/sidebar-acceptance.md).

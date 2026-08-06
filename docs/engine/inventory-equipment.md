---
type: Subsystem
title: Inventory and equipment gate
description: The M12 milestone gate - the first repeatable gameplay loop proved end to end,
  the World > Inventory & Equipment destination that drives and inspects it, ownership
  reporting, appearance-skip accounting, and the acceptance record.
tags: [engine, inventory, equipment, acceptance, app-ui, milestone]
timestamp: 2026-08-02T00:00:00Z
---

# Inventory and equipment gate

Milestone 12, item 12.2.4. The point at which OpenSky stops being a viewer with a world in
it and starts being a game loop: walk to a loose item, take it, open a container, transfer,
equip, buy, sell, drop, save, load, and find the world and the actors exactly as they were
left.

Nothing new happens in the engine here. Every capability the loop exercises landed in
[item and container records](/formats/actors.md), the inventory component under
[runtime state](/engine/runtime-state.md), the world-item layer under
[interaction](/engine/interaction.md), the equipment runtime, the
[inventory menu](/engine/inventory-menu.md) and the
[container and barter menus](/engine/barter.md). This page is what the gate added on top:
one sidebar destination for the three things that had no surface, two pieces of accounting
the loop needed to be checkable, and the record of what was verified.

## Contents

- [The loop](#the-loop)
- [Grants](#grants)
- [Ownership](#ownership)
- [Appearance skips](#appearance-skips)
- [Budgets](#budgets)
- [Verification](#verification)
- [Limits / next](#limits--next)

| Layer | File | Target |
|---|---|---|
| Panel seam | `opensky/Engine/InventoryEquipmentControlProviding.swift` | app + CLI |
| Readout text | `opensky/Engine/InventoryEquipmentReadout.swift` | app + CLI |
| Appearance-skip accounting | `opensky/Engine/World/CellSceneBuilderActors.swift` | app + CLI |
| Per-actor skip lookup | `opensky/Engine/World/CellStreamerInteraction.swift` | app + CLI |
| Renderer + AppKit wiring | `opensky/App/GameViewControllerInventoryEquipment.swift` | app |
| Verification surface | `opensky/App/InventoryEquipmentPanelViewController.swift` and `opensky/App/Shell/Sections/InventoryGrants*.swift`, `ItemOwnership*.swift`, `EquipmentInspection*.swift` | app |

## The loop

Nine steps, each one a real runtime call with its own accounting:

| Step | Call | What must hold |
|---|---|---|
| Grant | `InventoryRuntime.add` | the only step that creates items, and it says so |
| Take | `WorldItemRuntime.take` | the item enters an inventory, the reference is deleted in its own cell |
| Transfer | `ContainerSession.deposit` / `take` | both sides change, the total across them does not |
| Equip | `EquipmentRuntime.equip` | the equipped set is written to the actor's cell; a conflicting piece displaces rather than stacks |
| Buy | `BarterSession.buy` | gold one way, the item the other, in one write |
| Sell | `BarterSession.sell` | the merchant pays less than it charged, and gold is still conserved |
| Drop | `WorldItemRuntime.drop` | one item leaves the player, one spawned reference appears |
| Save | `OpenSkySaveStore.save` | the whole delta, allocator position included |
| Load | `WorldStateStore.restore` | a brand-new store is in the identical end state |

Conservation is the through-line: after the grant, no step creates or destroys anything.
The gate reads the totals rather than assuming them, because the fixture chest's `CNTO`
baseline resolves a leveled list and how much it holds is the data's answer to give.

Refusals are ordinary outcomes that write nothing. A merchant with an empty purse still
sells its whole stock, a player who cannot afford a sword keeps their gold, and equipping
what an owner does not hold is a typed failure that leaves the equipped set untouched.

## Grants

`grantItem(_:count:to:)` is a developer control with no analogue in the shipping game. It
exists because the loop needs a known item in a known inventory before it can move one, and
hunting the world for one is neither repeatable nor something an acceptance record can
name. It is `InventoryRuntime.add` and nothing more, so a granted stack lands in the
journal, the dirty counts and the save exactly as a taken one does.

Two refusals, both stated rather than silent: a non-positive count, and a form no loaded
plugin describes. The second matters because an unknown form has no weight, value or name,
and a stack of one would put a number the data never authored into the accounting.

Grants land in the player's inventory or the open container's. A merchant is a container,
so nominating one under `World > Container Menu > Merchant` and opening it makes this the
merchant's stock too — which is how the gate stocks a merchant without a `VENDR`-style
faction system existing.

## Ownership

`XOWN` and `XRNK` decode in `PlacedReference` and are reported for whatever the crosshair
is on. Ownership is decoded but not enforced: taking an owned item is theft in the data and
nothing in the engine stops it, because a crime system is not in this milestone. The
readout says so, rather than letting silence imply enforcement.

Three conditions read as three different answers, never as a blank:

- no crosshair target at all,
- a target with no owner ("taking this is not theft"),
- a target with an owner, plus the faction rank when one is authored.

A null `XOWN` is unowned rather than owned by form zero, which is the decoder's rule and not
this panel's.

## Appearance skips

`AppearanceSkip` has always existed inside `ActorVisualResolution` and, until this
milestone, only reached a log line for actors that failed to render at all. That left a
real gap: a piece of an equipped set that occupies a slot and draws nothing is
indistinguishable from an equip that silently did nothing.

`ActorBuildCounts.appearanceSkipReasons` now records every skip for every assembled actor,
rendered or not, as `ACHR <id>: <reason> (<subject>)`, and `CellLoadSummary` carries the
list. Only the `.appearance` subject is taken: the other `ActorAssemblySkip` subjects are
asset-loading outcomes, which the failure buckets already own, and mixing the two would
make a missing NIF read as a resolution decision.

The list sits deliberately outside the cell's exact-accounting identity. An actor whose
skin torso is masked by its equipped cuirass renders perfectly and still reports a skip;
counting that as a failure would break the identity for a case that is the outfit working.

`CellStreamer.appearanceSkipReasons(forActor:)` filters the resident cells' summaries by
the `ACHR <id>:` prefix, trailing space included. Matching on a prefix rather than keeping
a per-actor map is deliberate: a cell holds a handful of actors, a rebuild rewrites the
whole list, and an index would be a second structure to keep in step for no gain.

## Budgets

No new budget mechanism. `M12AcceptanceBudgetTests` runs the shipping validators —
`validatedActorBuildMetrics` and `validatedFlyUpdateBudgets` — over the shipping
`CellStreamingFlyBenchmarkConfiguration`, so the numbers the CLI bench enforces are the
numbers the gate asserts. A cell whose actor is dressed from a runtime equipped set stays
inside the actor-build budget, the new skip list does not disturb the accounting the same
validator checks alongside the timing, and an over-budget build still produces the existing
reason-tagged error.

Frames rendered with a menu open meet the animation, audio and script update budgets by
construction rather than by luck: menu mode advances every sim clock by zero, so a paused
frame does no per-frame update work at all. Measured timings against the real install come
from `openskycli bench --fly-path`, which cannot run in a unit test.

## Verification

Sidebar path **World > Inventory & Equipment** (`Destination-inventoryEquipment`), three
sections: `PanelSection-inventoryGrants`, `PanelSection-itemOwnership` and
`PanelSection-equipmentInspection`. Controls: `InventoryGrantFormIDField`,
`InventoryGrantCountField`, `InventoryGrantTargetControl`, `InventoryGrantControl`,
`EquipmentInspectionTargetControl`. Readouts: `InventoryGrantsStatsLabel`,
`ItemOwnershipStatsLabel`, `EquipmentInspectionStatsLabel`.

The loop's other halves are not duplicated here and the record names where they live:
take, search, take-all, drop, equip and unequip are `World > HUD & Interaction > Items`
(`ItemsTakeControl` and its siblings, `ItemsStatsLabel`); merchant nomination and the
buy/sell transactions are `World > Container Menu` (`ContainerMerchantSelectControl`,
`ContainerMenuBarterControl`, `ContainerMenuStatsLabel`); saving and loading are
`World > Runtime State > Save` (`RuntimeStateSaveControl`, `RuntimeStateLoadControl`). Two
sidebar paths owning one control would be worse than one path owning it and this record
naming both.

Inspecting the player rather than the nearest NPC is the destination's one departure from a
documented default, so it is what the sidebar dot and "Reset all" act on. Granting
deliberately does not light it: a grant is a world change, and `World > Runtime State`
already owns resetting those.

Covering tests:

- `M12AcceptanceTests` — the whole loop in one scripted run over a synthetic plugin, with
  the accounting checked at every step, plus ownership reaching the readout and the refusal
  paths writing nothing.
- `M12AcceptanceRenderTests` — the pixel evidence, device-gated. The taken item's pixels
  leave and the dropped one's return, measured as changed-pixel counts and cross-checked:
  a taken cell is byte-identical to a cell that never held the item, and a dropped one is
  byte-identical to a cell whose plugin placed it. The equipped actor's silhouette changes,
  with re-equipping the outfit's own piece as the control.
- `M12AcceptanceBudgetTests` — the budget gates above.
- `InventoryEquipmentPanelTests` — accessibility ids, section order, grant refusals,
  the ownership and equipment readouts, and the override/reset contract.
- `InventoryEquipmentReadoutTests` — every readout line as a pure function of one snapshot.
- `DestinationRegistryInventoryEquipmentTests`, `DestinationRegistryTests`,
  `AppSidebarModelTests` — placement, factory wiring and the id contract.

Local A/B capture: none. A frame OpenSky renders from a real install embeds Bethesda
assets, so captures stay in gitignored `logs/` and are never committed; the deterministic
tests above are the evidence
([sidebar acceptance](/tools/sidebar-acceptance.md)).

## Limits / next

- Ownership is reported, never enforced. Stealing, bounties and the crime system are M18+.
- The player has no rendered body until M14, so equipping on the player is a state-only
  operation and its appearance-skip list is empty by construction rather than by omission.
- A merchant is still a nominated container. Faction-linked vendor chests need `VENDR`-style
  data that is not decoded.
- A dropped object whose mesh carries a simulated Havok body now settles under
  [dynamic rigid bodies](/engine/dynamic-bodies.md) (issue #193): `dropHeight` became the
  release pose rather than the resting one. An object whose mesh carries no dynamic body
  still rests where the drop placed it.
- Carry weight is computed and shown but nothing is encumbered by it.

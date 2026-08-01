---
type: Subsystem
title: Interaction targeting
description: Walk-mode view-ray targeting, record labels, typed events, and door dispatch.
tags: [engine, interaction, collision, streaming]
timestamp: 2026-07-26T00:00:00Z
---

# Interaction targeting

M8.4.1 gives the use key one engine-owned path shared by ordinary activators and doors.
The current crosshair target is a value, and pressing F emits a typed activation event.
HUD prompts and the later Papyrus `OnActivate` bridge can subscribe without reimplementing
selection. Implementation: `Interaction.swift`, `InteractionRaycast.swift`,
`CellStreamerInteraction.swift`.

## Scene metadata

`CellSceneBuilder` resolves interaction metadata while it already owns plugin records and
localized strings. Each eligible placed reference retains:

* REFR FormID, base FormID, and world position;
* display name from base `FULL`, then `EDID`, then the base FormID;
* typed action and label.

The first actions are DOOR `Open`, CONT `Search`, ACTI `Activate`, TREE `Harvest`, and FURN
`Activate`. M12.1.3 adds `Take` for the six carryable families — `MISC`, `WEAP`, `AMMO`,
`ALCH`, `INGR`, `BOOK` — which joined `ModelBase.supportedTypes` in the same issue, so a
loose item reference now resolves a model, a collision shape and interaction metadata
instead of counting as an unsupported base. ACTI `RNAM` overrides its action label. `FULL`
and `RNAM` are lstrings, so a localized plugin resolves both through its `.strings` table.
These English default verbs are provisional until GMST-backed localized action labels land.

`ARMO` is deliberately not in that set even though it is carryable. Its world model is
`MOD2`/`MOD3` and body pieces resolve through `ARMA` addons rather than a single `MODL`, so
it needs the arbitration that belongs to the equipment milestone.

MSTT remains non-interactive. The builder also excludes ACTI records whose header has
`Ignore Object Interaction`, automatic DOOR records, and FURN records whose marker flags
disable activation. The layouts and open-spec citations are in
[record decoders](/formats/records.md).

## Selection

`GameViewController` supplies the camera view ray only in walk mode. Fly mode supplies nil,
which clears the published target and makes F a no-op. A ray is normalized, finite, and
limited to 192 world units.

The broadphase queries resident static-collision BVHs with the ray segment bounds. Exact
narrowphase tests triangle soup, convex triangle faces, boxes, spheres, and capsules after
transforming the ray into each shape's local space. Keeping the original ray parameter
through the inverse transform preserves world distance under rotation and non-uniform scale.
Equal-distance hits use the lower REFR FormID for deterministic selection.

The engine selects the nearest collision first and only then looks up interaction metadata.
This ordering makes an ordinary wall occlude an activator behind it. It also establishes the
current limitation: a placed object without player-solid decoded collision cannot be
targeted yet.

## Activation

Target changes publish `InteractionTarget`, containing the placed interaction, exact hit
position, and distance. F publishes one `InteractionEvent` for the current target.

That event is multicast. `CellStreamer.onInteraction` is a `CallbackFanOut<InteractionEvent>`
rather than one optional closure, so several subscribers coexist and registration order is
delivery order. `GameViewController` registers two: world audio first
(`WorldAudioSoundDirector.handleInteraction`, which plays the activation sound), then the
Papyrus activation bridge (`PapyrusWorldStateBridge.handleInteraction`, which records the
activation and queues `OnActivate`). Papyrus subscribes beside the engine's own behavior and
never replaces it — the raycast, the recorded activation, the door transition and the sound
are independent consequences of the same event.

The event carries a load-order-relative `FormID`, so the Papyrus subscriber maps it to a
session-stable `ReferenceKey` through `CellStreamer.referenceEntry(formID:)` before writing
anything; an event for a reference no resident cell knows is dropped rather than recorded
under a guessed identity. The details of what it then writes are in
[Papyrus virtual machine](/engine/papyrus-vm.md) and
[runtime state](/engine/runtime-state.md).

DOOR uses that same event path. When the selected interaction has action `Open`, the
streamer requests a transition for that exact REFR. A door with XTEL follows the existing
interior/exterior transition path; a door without XTEL still emits the interaction event
but has no built-in animation yet.

## World items

`WorldItemRuntime` (M12.1.3) is the third subscriber to that event, registered after audio
and Papyrus so the activation sound and the recorded activation both land whether or not
the take succeeds. It is headless and menu-free: taking an object is a world operation, and
the engine performs it with no interface attached. The panel controls and the future menus
(#289, #179) drive the same three entry points the use key does.

Everything it does is one `WorldStateStore` write, so the journal, the per-cell dirty
counts, the cell rebuild and the save see it without this layer arranging any of them:

| Operation | Inventory arithmetic | World write |
| --- | --- | --- |
| Take | `InventoryRuntime.add` into the player | `ReferenceDeletionState` on a plugin placement, a full `reset` on a spawned one |
| Drop | `InventoryRuntime.remove` from the player | `ReferenceSpawnState` under a freshly allocated generated key |
| Container transfer | `InventoryRuntime.transfer` both ways | none — only the items move |

Ordering inside each operation is chosen so a failure writes nothing: the throwing
arithmetic runs first, and the world write happens only once it has succeeded. A take that
would overflow the player's stack therefore leaves the item lying in the world rather than
deleting it into nowhere. How many items one reference stands for is its `XCNT`, or its
spawned stack count, or one; a non-positive `XCNT` reads as one, because a reference that is
placed in the world is at least one item.

A take on a *spawned* object resets its whole delta rather than marking it deleted. The
object exists only because the store says so, so dropping the state is what makes it gone,
and it leaves no tombstone to accumulate in every later save.

### Container sessions

`ContainerSession` is a live handle on one container reference, not a snapshot of it:
`contents` reads through `InventoryRuntime` on every access, so a script that empties the
chest while the session is open is visible on the next read. It offers `contents`,
`take(_:count:)`, `takeAll()`, `deposit(_:count:)` and `close()`. Each individual transfer
is all-or-nothing, so no count is ever lost; `takeAll()` is deliberately not atomic across
stacks, because the only way a later stack can fail is an overflow on a player stack of over
two billion and stopping there having moved the earlier stacks beats refusing to empty a
chest.

Open state is recorded on `ReferenceActivationState.isOpen`, written by the session and set
explicitly rather than toggled. The Papyrus activation bridge toggles `isOpen` for doors,
where one activation is one swing; a container's open state is the lifetime of a session,
and only the session knows when that starts and ends.

### Drop placement

A dropped object lands one step in front of the camera and one standing height below it —
`WorldItemRuntime.dropForwardOffset` and `dropHeight`, both static offsets rather than
physics results. The forward vector is flattened onto the ground plane first, so looking at
the sky does not throw the item over the player's head; a camera pointing straight up or
down leaves nothing to flatten and the object lands directly below the eye. Havok-style
settling waits for M15. Which cell the object belongs to comes from
`CellStreamer.currentCellLocation`: the interior when one owns the view, otherwise the
exterior grid center.

What happens to the spawned object afterwards — how it is identified, how a build places it,
and how it is saved — is [runtime state](/engine/runtime-state.md).

## World > HUD & Interaction > Items

The panel section is the milestone's acceptance surface. `Take target` and `Search target`
act on whatever the walk-mode crosshair is on, exactly as the use key does; `Take all` and
`Close container` drive the open session; `Drop` places a `FormID` from the field, or the
player's first stack when it is blank, at the count beside it. The readout under the buttons
states the target and whether it is takeable, the player's stacks with carry weight and gold,
the open container's contents, how many objects the session has spawned, and the outcome of
the last action.

The section carries no override state of its own. Taking and dropping are world changes
recorded in `WorldStateStore`, and `World > Runtime State` already owns resetting those;
a second reset here would give the same deltas two owners.

## HUD publication

M8.4.2 subscribes the vanilla `hudmenu.swf` bridge to target changes. The callback only
records the new value and marks derived state dirty; the renderer frame hook applies prompt,
compass-marker, and camera-heading changes together between frames.

The prompt is the interaction action label plus its resolved name, so a selected door shows
`Open <door name>`. The compass publishes one location marker at the placed reference
position rather than the collision hit point, which keeps its heading stable while the ray
moves across the same object. Clearing the target hides the prompt and removes the marker.
Activation and door dispatch remain on the typed event path above; the HUD is a subscriber,
not a second interaction system.

`World > HUD & Interaction > Target` is the durable inspection surface. It publishes the
selected REFR and base FormIDs, resolved action and name, ray distance, placed and collision-hit
positions, the exact prompt sent to the movie, camera heading, and target-marker headings. The
readout is deliberately live-only: it does not provide a synthetic target that could hide a
selection or localization failure.

## Verification

The M12.1.3 acceptance record, in the format
[sidebar acceptance](/tools/sidebar-acceptance.md) defines:

```text
Milestone: M12.1.3
Sidebar path: World > HUD & Interaction > Items
Destination id: Destination-hudInteraction
Controls exercised: ItemsTakeControl, ItemsSearchControl, ItemsTakeAllControl,
  ItemsCloseContainerControl, ItemsDropControl, ItemsDropFormIDField, ItemsDropCountField
Readout: ItemsStatsLabel
Deterministic tests: ItemsSectionTests, DestinationRegistryTests, WorldItemRuntimeTests,
  ContainerSessionTests, CellSceneBuilderSpawnTests, CellStreamerSpawnTests,
  WorldItemRealDataTests (env-gated, make realtest)
Local A/B (optional, never committed): none
```

Synthetic coverage of the item path exercises the take, drop and container operations above
the store, the accessibility-id contract and readout spelling of the section, a spawned
object resolving a model and a collision shape at its placement through the real
`CellSceneBuilder`, and the streaming behaviour — rebuild on drop, eviction and reload, the
in-flight-build race, and a save/load cycle. The test classes are listed per area in
[runtime state](/engine/runtime-state.md).

`WorldItemRealDataTests.swift` is the env-gated sweep over the local install, run with
`make realtest`. Over the 5x5 Whiterun-area exterior grid on Skyrim.esm (2026-08-01) it
finds 50 `.take` references across 25 cells — 24 distinct names — and all 50 resolve in
`ItemDefinitionStore`, so every loose item the widened base set exposes can be weighed,
valued and stacked. The same build drew 1432 references in total. Numbers go to gitignored
`logs/world-items-sweep.txt`; the record dump itself is game content and is never committed.
`CellRenderRealDataTests` still renders the launch cell at 16 refs / 16 drawn / 0 skipped
after the widening, so making six more base types drawable broke no existing resolution.

Synthetic coverage of targeting exercises every supported collision primitive, transformed world
distance, inside-shape exits, invalid input, range rejection, deterministic ties, target
publication and clearing, wall occlusion, localized/inline record text, record suppression,
action resolution, activation events, selected-door transitions, prompt mapping, and compass
heading derivation. The M4 walk benchmark now enters and exits through the selected
interaction target instead of proximity dispatch.

The environment-gated M8.4.3 acceptance builds the real walk-route farm cell `(7,-3)`, resolves
DOOR REFR `0001633D`, and raycasts its installed NIF collision through the same exact narrowphase.
The hit was 83.329315 units away and produced the live prompt `Open Door`. Publishing only that
prompt to the installed HUD movie changed 7,509 pixels at 1280x720. Prompt-off/on frames and the
numeric report stay under gitignored `logs/`; a local A/B inspection confirmed the prompt appears
at the crosshair while the compass and crosshair stay stable.

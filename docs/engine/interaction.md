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
`Activate`. ACTI `RNAM` overrides its action label. `FULL` and `RNAM` are lstrings, so a
localized plugin resolves both through its `.strings` table. These English default verbs
are provisional until GMST-backed localized action labels land.

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

Synthetic coverage exercises every supported collision primitive, transformed world
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

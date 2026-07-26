---
type: Subsystem
title: World SFX + ambience
description: World SFX director that wires interaction events to one-shot SFX and
  per-cell context to a positional ambience bed; the M9.2.2 verification surface.
tags: [engine, audio, sfx, ambience]
timestamp: 2026-07-26T00:00:00Z
---

# World SFX + ambience

Milestone 9.2.2 (issue #155): wire the [decoded sound records](/formats/sound.md)
to the [world interaction system](/engine/interaction.md) and the streaming cell
lifecycle. Door open SFX on use-key activation; per-cell ambient bed under the
provisional `ambience` category. Implementation: `opensky/Audio/WorldAudioSoundDirector.swift`
(director), `opensky/Audio/AmbienceCatalog.swift` (bed resolution),
`opensky/Audio/AcousticSpaceStore.swift` (ASPC index),
`opensky/World/CellStreamerAmbience.swift` (streamer emission), and the panel
section `opensky/Shell/Sections/AudioSfxSection.swift`.

## Subscriptions

The director subscribes to two `CellStreamer` callbacks. Both are no-ops until
the user enables the [world audio engine](/engine/audio.md).

```text
CellStreamer.onInteraction  -> director.handleInteraction  -> play activation SFX
CellStreamer.onAmbienceContextChanged -> director.handleAmbienceContext -> bed swap
```

`onInteraction` is the typed-event seam M8.4.1 introduced and reserved for "the
later Papyrus OnActivate subscriber"; that future subscriber will listen
alongside the director, not replace it.

### Activation SFX

A use-key press publishes one `InteractionEvent` carrying the target's
`PlacedInteraction.sounds` (resolved at cell-build time from
[ModelBase sound fields](/formats/records.md)). The director plays the
`activation` FormID under the `effects` category at the placed reference's
position. Close and loop sounds ride along on the same struct but wait on door-
animation wiring (issue #234).

### Ambience bed

The streamer's `emitAmbienceContextIfNeeded` builds an `AmbienceContext` value
from the current center cell and fires it on `onAmbienceContextChanged`
whenever the context key changes:

* exterior center cell -> XCLR regions
* interior scene -> XCAS acoustic space, plus the interior-cell FormID

The director's `AmbienceBed.resolve` produces a deterministic ordered list of
SNDR/SOUN FormIDs from that context:

* exterior: each region's type-7 RDAT sound area (`RDSA` entries)
* interior: `ASPC.SNAM` direct plus `ASPC.RDAT`-borrowed region's sound area

The bed is diffed against the previous one; only changes retire + restart
sources. `apply(transition:)` forces a re-emit on scene swaps so an interior
re-entered with the same key still refreshes.

## Threading

Main-actor only, like the rest of the audio engine. Decode work runs inside the
engine's existing decode queue; nothing OpenSky-side runs on the audio render
thread. The stores (`SoundRecordStore`, `WeatherStore`, `AcousticSpaceStore`)
are immutable value-type indices after construction, so the director reads them
freely from the main thread.

## Sound resolution

`SoundRecordStore.resolveAny` follows the SOUN-legacy-marker hop
(`SOUN.SDSC -> SNDR`) automatically — activator/door/container sound fields
store raw FormIDs whose target type is not pinned at decode time. A probe
against Skyrim.esm (2026-07-26) found vanilla SSE ships zero SOUN markers on
these records: all 497 references target SNDR directly. The hop is supported
anyway because xEdit allows it.

## Positional stopgap

Ambience plays positional at the listener position when started, not as a
non-positional bed. Source lifetime is bounded by:

* the engine's existing FIFO cap (`maxConcurrentSources = 8`)
* the engine's existing cell-purge (3-ring Chebyshev distance)
* the director's own retire-on-context-change

The stopgap means a started ambience source stays at its initial position
while the player walks away, attenuating. The fix is the planned non-positional
bed path through the existing `categoryMixers[.ambience]` submix (issue #236);
until then the equal-weight gain split keeps N concurrent loops from summing
to N x master.

## World > Audio > SFX & Ambience surface

Sidebar path for acceptance: **World > Audio > SFX & Ambience**
(`PanelSection-audioSfx`). The section carries:

* `AudioSfxEnabledControl` checkbox — toggles `sfxEnabled` (default on).
* `AudioAmbienceEnabledControl` checkbox — toggles `ambienceEnabled`
  (default on).
* `AudioStopAmbienceControl` button — force-retires the current bed; the next
  cell change restarts it. A/B inspection helper.
* `AudioSfxStatsLabel` readout — last SFX description (or "none"), last SFX
  error, and the current ambience bed (FormIDs joined, or "none").

Override aggregation: the audio destination's `isOverridden` unions
`AudioOutputSection` and `AudioSfxSection`; reset all clears both.

## Verification

* `ModelBaseSoundTests`, `CellRecordTests`, `RegionRecordTests`,
  `AcousticSpaceRecordTests` — synthetic ESM field coverage for every decoded
  field the director consumes.
* `AmbienceCatalogTests` — bed resolution for exterior/interior, unknown-region
  skip, missing-ASPC, ASPC-without-direct-or-borrow.
* `WorldAudioSoundDirectorTests` — offline-render coverage: interaction plays
  activation sound, ambience starts/stops on context change, no-op when
  disabled, force trigger, resolve-failure error.
* `CellStreamerAmbienceTests` (under `CellStreamerTests`) — streamer emits
  context on cell arrival, dedups steady-state, regionless center emits empty.
* `AudioPanelTests` — id contract for the new controls + round-trip test
  through the provider.
* Env-gated probe (`make probe` 2026-07-26 against Skyrim.esm): 45 ASPC, 53
  REGN with sound area, 687 RDSA entries, 497 activator/door/container sound
  references all resolve to SNDR (0 SOUN markers in vanilla); RDSA.Chance range
  pinned at 0.01-1.0.

Audible acceptance is a human step: open World > Audio, tick Enabled, walk a
Whiterun exterior cell (regions carry ambient beds), press F on a door (open
SFX under effects), enter an interior (XCAS-sourced bed under ambience).
Toggle `AudioSfxEnabledControl` to confirm SFX mute independently from the bed.

## Follow-ups filed

* #234 — door close SFX (needs door-animation event).
* #235 — rename `AudioCategory` from the provisional taxonomy.
* #236 — non-positional ambience bed path through the existing submix.
* #238 — comprehensive Cell decoder unit tests (pre-existing gap, widened by XCAS).

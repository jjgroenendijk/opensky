---
type: Subsystem
title: World SFX + ambience
description: World SFX director that wires interaction events to one-shot SFX and
  per-cell context to a non-positional ambience bed; the M9.2.2 verification surface.
tags: [engine, audio, sfx, ambience]
timestamp: 2026-08-01T00:00:00Z
---

# World SFX + ambience

Milestone 9.2.2 (issue #155): wire the [decoded sound records](/formats/sound.md)
to the [world interaction system](/engine/interaction.md) and the streaming cell
lifecycle. Door open SFX on use-key activation; per-cell ambient bed under the
descriptor's authored `SNDR.GNAM` category. Implementation:
`opensky/Audio/WorldAudioSoundDirector.swift`
(director), `opensky/Audio/AmbienceCatalog.swift` (bed resolution),
`opensky/Audio/AcousticSpaceStore.swift` (ASPC index),
`opensky/World/CellStreamerAmbience.swift` (streamer emission), and the panel
section `opensky/Shell/Sections/AudioSfxSection.swift`.

## Contents

* [Subscriptions](#subscriptions)
* [Threading](#threading)
* [Sound resolution](#sound-resolution)
* [Non-positional ambience routing](#non-positional-ambience-routing)
* [World > Audio > SFX & Ambience surface](#world--audio--sfx--ambience-surface)
* [Verification](#verification)
* [Follow-ups filed](#follow-ups-filed)

## Subscriptions

The director subscribes to three `CellStreamer` callbacks. All are no-ops until
the user enables the [world audio engine](/engine/audio.md).

```text
CellStreamer.onInteraction  -> director.handleInteraction  -> play activation SFX
CellStreamer.onInteractionAnimation -> director.handleInteractionAnimation
  motionStarted -> start authored loop
  closed        -> stop loop + play close SFX
  cancelled     -> stop loop
CellStreamer.onAmbienceContextChanged -> director.handleAmbienceContext -> bed swap
```

`onInteraction` is the typed-event seam M8.4.1 introduced and reserved for "the
later Papyrus OnActivate subscriber"; that future subscriber will listen
alongside the director, not replace it.

### Activation SFX

A use-key press publishes one `InteractionEvent` carrying the target's
`PlacedInteraction.sounds` (resolved at cell-build time from
[ModelBase sound fields](/formats/records.md)). The director resolves the
`activation` FormID, follows its descriptor's `SNDR.GNAM -> SNCT.PNAM` chain to
a vanilla menu category, and plays it at the placed reference's position.
Missing or malformed category metadata falls back to Effects.

### Door motion and close SFX

An accepted player-driven door transition publishes an
`InteractionAnimationEvent.motionStarted` boundary and retains the source
`PlacedInteraction` across the asynchronous destination build. A successful
build publishes `closed` immediately before replacing the source scene; a
failed build publishes `cancelled`. Runtime-state rebuild transitions publish
none of these player-audio events.

The director starts `sounds.loop` as a positional looping source on
`motionStarted`. It records that source ID under the placed reference so
`closed` and `cancelled` retire exactly the movement loop without disturbing
ambience or other effects. `closed` then resolves and plays `sounds.close` as a
one-shot. This covers `DOOR BNAM` and `DOOR ANAM`; the same typed event accepts
`CONT QNAM` when container animation becomes a producer. A future rendered
door animation moves the existing phase emission to its authored boundaries;
the audio subscription and resolution path do not change.

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

### Bed lifetime and the enable toggle

A bed is continuous, so every bed source starts with
`AudioPlayRequest.loops = true`: at end of file its streamer resets the decoder
and rewinds to the first packet instead of reporting completion, and the audio
tick therefore never retires it (see
[looping in the audio engine](/engine/audio.md)). Without that a "bed" would
play through exactly once and fall silent until the center cell changed.

The director keeps two pieces of state and one path between them:

* `desiredBed` — the bed the last `AmbienceContext` resolved to, whether or not
  it is playing. It is what a context change diffs against, and what gets
  started when ambience is switched back on.
* `ambienceSourceIDs` — the ids of the bed sources actually started, so
  `WorldAudioEngine.stopSource(id:)` retires exactly this bed and leaves
  concurrent one-shot SFX playing.

Both a context change and the `ambienceEnabled` toggle go through the same
`applyAmbienceState()`: retire what is playing, then start `desiredBed` when
ambience is enabled and the engine is running. So unticking the checkbox stops
the bed immediately, ticking it restarts the bed the last context resolved (no
waiting for the next cell change), and a context that arrives while ambience is
off is remembered rather than swallowed.

The readout is derived from live sources, not from the resolved bed: ids the
engine already stopped because the graph shut down or a stream could not
produce audio are pruned first, and `currentAmbienceDescription` reports `none`
when nothing of this director's is still playing. It therefore cannot claim a
bed is playing when it is not.

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

The resolved descriptor also supplies the runtime category. Skyrim's ambience
nodes are children of `AudioCategorySFX`, so current vanilla SFX and ambience
both reach the Effects factor. The same resolver already handles Footsteps,
Voice, and Music without hardcoded FormIDs.

## Non-positional ambience routing

Each ambience entry starts through `WorldAudioEngine.playNonPositional` and
connects directly to the submix for its descriptor's resolved vanilla category.
Vanilla ambience resolves under Effects, but routing follows the record rather
than hardcoding that category. The submix applies the category volume, mute and
solo factor once to the complete bed; each player node carries only unity source
gain and fade gain.

The bed has no world position, panning or distance attenuation. Moving the
listener therefore cannot make ambience fade away from the position where the
context began. Non-positional sources are outside the positional FIFO budget
and cell purge; the director owns their lifetime and retires them on context
change, through the ambience toggle, or when the user presses Stop ambience.

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

### Acceptance record

The record required by the
[sidebar verification convention](/tools/sidebar-acceptance.md), also carried as
one row in that page's ledger:

```text
Milestone: M9.2.2
Sidebar path: World > Audio > SFX & Ambience
Destination id: Destination-audio
Controls exercised: AudioSfxEnabledControl, AudioAmbienceEnabledControl,
  AudioStopAmbienceControl, AudioEnabledControl
Readout: AudioSfxStatsLabel
Deterministic tests: AudioPanelTests, DestinationRegistryTests,
  WorldAudioSoundDirectorTests, WorldAudioDirectorAmbienceTests,
  WorldAudioEngineTests, AudioSourceStreamerTests, AmbienceCatalogTests,
  CellStreamerTests, RecordDecoderTests, AcousticSpaceRecordTests,
  RegionRecordTests, CellRecordTests
Local A/B (optional, never committed): none
```

`AudioEnabledControl` lives in the Output section of the same destination and is
listed because nothing in this section produces sound until the world audio
engine is running. `CellStreamerTests` and `RecordDecoderTests` are the class
names the ambience and sound-field cases extend; the cases themselves live in
`openskyTests/CellStreamerAmbienceTests.swift` and
`openskyTests/ModelBaseSoundTests.swift`, so grepping for the class name finds
the base file, not the milestone's cases. No A/B capture applies: the behavior
this milestone adds is audible, not visible, so a rendered frame would prove
nothing.

## Verification

* `ModelBaseSoundTests`, `CellRecordTests`, `RegionRecordTests`,
  `AcousticSpaceRecordTests` — synthetic ESM field coverage for every decoded
  field the director consumes.
* `AmbienceCatalogTests` — bed resolution for exterior/interior, unknown-region
  skip, missing-ASPC, ASPC-without-direct-or-borrow.
* `WorldAudioSoundDirectorTests` — offline-render coverage: interaction plays
  activation sound (as a non-looping effect), motion starts the authored loop,
  close retires the loop and plays its one-shot, cancellation retires the loop
  without a false close, force trigger, and resolve-failure error. Fixtures
  shared with the ambience suite live in
  `openskyTests/WorldAudioDirectorFixtures.swift`.
* `WorldAudioDirectorAmbienceTests` — offline-render coverage of the bed:
  category-submix routing with no world position, survival across distant
  listener-cell movement, retire on context change, no-op when disabled, toggle
  retires and restarts, a context resolved while disabled starts on enable,
  bed sources are looping, retiring the bed leaves a concurrent one-shot SFX
  alive (`stopSource(id:)` selectivity), and the readout falls back to `none`
  once the engine has retired the bed.
* `WorldAudioEngineTests.loopingSourceKeepsPlayingPastItsMaterial` — offline
  render proving a looping request keeps sounding past the end of its material
  while a one-shot falls silent; `AudioSourceStreamerTests` covers the
  end-of-file rewind policy itself (pure, because no WMA fixture may enter the
  repository).
* `CellStreamerDoorTests` (under `CellStreamerTests`) — accepted player door
  transitions publish `motionStarted` followed by `closed`; failed transitions
  end in `cancelled`.
* `CellStreamerAmbienceTests` (under `CellStreamerTests`) — streamer emits
  context on cell arrival, deduplicates steady state, regionless center emits
  empty.
* `WorldAudioTransitionAcceptanceTests` — the M9 gate's transition sentence as
  one synthetic sequence: an exterior cell arrives and starts its region bed and
  exploration playlist, a door interaction plays its activation SFX without
  disturbing either, `apply(transition:)` swaps in an interior whose acoustic
  space supplies a new bed and whose cell music switches the state to interior,
  and the paired transition back restores both. This is the interior coverage
  `CellStreamerAmbienceTests` explicitly does not claim, because the
  exterior-center path never flips to interior on its own.
* `M9AudioAcceptanceRealDataTests` (env-gated, `make realtest`) — the route
  exterior cell's regions and the route interior's `XCAS` resolve to real beds,
  and the route door's base yields open and close descriptors resolving to real
  files. Report in gitignored `logs/m9-audio-acceptance.log`.
* `AudioPanelTests` — id contract for the new controls + round-trip test
  through the provider.
* Env-gated probe (`make probe` 2026-07-26 against Skyrim.esm): 45 ASPC, 53
  REGN with sound area, 687 RDSA entries, 497 activator/door/container sound
  references all resolve to SNDR (0 SOUN markers in vanilla); RDSA.Chance range
  pinned at 0.01-1.0.

Audible acceptance is a human step: open World > Audio, tick Enabled, walk a
Whiterun exterior cell (regions carry ambient beds), press F on a door (open
SFX under Effects), enter an interior (XCAS-sourced bed under Effects).
Toggle `AudioSfxEnabledControl` to confirm SFX mute independently from the bed.
The M9 gate asks for that route once end to end — exterior bed, door SFX,
interior bed, and back out through the paired door — with each change confirmed
by ear while `AudioSfxStatsLabel` names the sound and the bed. Nothing in the
repository records that anyone has done it: `WorldAudioTransitionAcceptanceTests`
proves the same sequence drives the directors, and
`M9AudioAcceptanceRealDataTests` proves the records behind it resolve on the
install, but the listening itself is still outstanding.

## Follow-ups filed

* #238 — comprehensive Cell decoder unit tests (pre-existing gap, widened by XCAS).

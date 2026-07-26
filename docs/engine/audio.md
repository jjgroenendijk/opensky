---
type: Subsystem
title: World audio playback
description: AVAudioEngine graph with 3D positional sources, non-positional submix
  playback, gain ramps, streaming WMA decode, provisional category volumes, source
  budget, and the World > Audio surface.
tags: [engine, audio, playback, spatial]
timestamp: 2026-07-26T00:00:00Z
---

# World audio playback

Milestone 9.1.3: the runtime that turns a decoded `.xwm` payload into an
audible, positioned sound, plus the sidebar surface that verifies it without
the CLI. Consumes the [xWMA container parser](/formats/xwm.md) and the
[vendored ffmpeg WMA decoder](/decisions/ffmpeg-audio.md). Implementation:
`opensky/Audio/WorldAudioEngine.swift` (graph, volumes),
`WorldAudioEngineSources.swift` (source lifecycle),
`WorldAudioEngineFades.swift` (gain ramps),
`WorldAudioEngineSnapshot.swift` (published UI state),
`AudioSourceStreamer.swift` (streaming decode), `AudioSpace.swift` (coordinate
conversion), `AudioCategory.swift` (provisional categories),
`AudioCodecParametersXWM.swift` (extradata policy), and
`opensky/Rendering/RendererAudio.swift` (the per-frame tick).

## Graph

One `AVAudioEngine` per app, owned by `GameViewController`, created on first
enable and handed to the renderer for the per-frame tick:

```text
positional AVAudioPlayerNode (mono, one per source)
    --> AVAudioEnvironmentNode --> main mixer --> output device
non-positional AVAudioPlayerNode (stereo, one per source)
    --> category submix AVAudioMixerNode (music/effects/ambience) --->--/
```

* The environment node does the 3D mixing. Its inputs must be **mono** — it
  passes stereo through without spatializing — so streamed stereo sources are
  downmixed (`AudioSourceStreamer.monoDownmix`, channel average).
* Per-source rendering algorithm is `.equalPowerPanning`: deterministic and
  cheap, which is what the offline-render tests need. HRTF selection is a
  later decision alongside the M9.2 attenuation data.
* Category submixes carry the **non-positional** path: a source with no world
  position (music, and any other 2D bed) keeps the file's own channel layout,
  connects straight into `categoryMixers[category]`, and gets no panning, no
  distance attenuation and no position. A positional source cannot route
  through a submix — each needs its own environment-node input — so it carries
  its category factor at its player node instead.
* Routing is explicit, not inferred from the category: `AudioRouting`
  (`.positional` / `.nonPositional`) is recorded on `ActiveAudioSource` by the
  play call that started it, and surfaces in the snapshot as `isPositional`.
* Volumes multiply as: **effective gain = master x category x source x fade**.
  Master is `mainMixerNode.outputVolume`; the fade is the ramp factor below.
  The category factor is applied **exactly once**: at the player node for a
  positional source, at the submix for a non-positional one (applying it at
  both would square it). The player node's `volume` therefore holds
  `category x source x fade` when positional and `source x fade` when not.
  Distance attenuation applies after all of it, and only to positional sources.
* **Mute and solo** (M9.2.4) are two more per-category filters folded into the
  same category factor, `WorldAudioEngine.audibleVolume(for:)`: it returns the
  category's volume when the category is audible and zero when the category is
  muted or when a *different* category is soloed. Every gain path reads that
  one function — the submix output volumes, the positional player-node volumes,
  and the snapshot's `effectiveGain` — so the three can never disagree, and
  changing either filter re-applies them through `applyVolumesToSources()`, so
  sources that are already playing react on the call.
  * **Precedence**: mute and solo are independent filters and *both* must pass.
    Solo overrides nothing about mute, so soloing a category that is explicitly
    muted leaves it silent; unmuting it is the only way to hear it.
  * Mute is separate state from the volume (`mutedCategories`, a set, next to
    `categoryVolumes`), so unmuting restores exactly the level the slider was
    left at rather than snapping back to full.
  * Solo is a single optional category (`soloedCategory`), so it is mutually
    exclusive by construction; nil means nothing is soloed.
* Engine off by default; enabling it in the panel starts it. A start failure
  (no output device) is captured as `unavailableReason` and shown in the
  readout — it never crashes and never blocks the render loop.

## Coordinate conversion (world -> listener)

Skyrim's world is right-handed Z-up in native units (+X east, +Y north, +Z up,
1 unit = 0.0142875 m, exterior cell = 4096 units ~ 58.5 m —
[coordinates](/decisions/coordinates.md)). `AVAudioEnvironmentNode` listener
space is right-handed Y-up, and its distance parameters share the position
unit, which OpenSky fixes as **meters**. `AudioSpace` implements:

| world (Z-up, units) | listener (Y-up, meters) |
| ------------------- | ----------------------- |
| position `(x, y, z)` | `(x, z, -y) * 0.0142875` |
| direction `(x, y, z)` | `(x, z, -y)` (no scale) |
| +X east | +X |
| +Y north | -Z (straight ahead of a default listener) |
| +Z up | +Y |

This is the same `(x, y, z) -> (x, z, -y)` basis change as
`MatrixMath.zUpToYUp`. Listener orientation comes from the free-fly pose:
forward `(cos yaw * cos pitch, sin yaw * cos pitch, sin pitch)` and its
orthogonal up vector, both mapped through the direction conversion. Pinned by
`AudioSpaceTests` and, end to end, by the offline-render panning tests
(`WorldAudioEngineTests`): a source on the listener's right (world -Y when
facing +X) renders right-channel dominant.

## Threading model

Three domains, with one crossing type each:

1. **Main actor** — `WorldAudioEngine`, `GameViewControllerAudio`, the panel.
   Owns the graph, volumes, source list and listener pose. The renderer's
   `updateAudioFromWallClock()` (main thread, `draw(in:)`) pushes the camera
   pose and runs retirement/purge each frame, gated on `worldSimPaused`
   through its own `FrameSimClock`.
2. **Audio decode queue** — one serial `DispatchQueue` owned by the engine.
   Each `AudioSourceStreamer` confines its `WMADecoder` (not `Sendable` — one
   queue owns one instance) and all scheduling state here. It decodes
   16-packet chunks (~0.75 s) into PCM buffers and keeps at most 3 scheduled
   ahead via `AVAudioPlayerNode.scheduleBuffer`, so a music track never
   materializes whole (~37 MB of PCM; issue #218). Buffer completion handlers
   fire on an AVFAudio internal queue and immediately hop back to the decode
   queue to top up.
3. **Audio render thread** — runs **no OpenSky code**. `AVAudioPlayerNode`
   consumes the scheduled buffers there itself. Nothing OpenSky-side
   allocates, locks or logs on it because nothing OpenSky-side runs on it.

Crossings: main -> queue is `start()`/`requestStop()` (async, no waiting);
queue -> main is a single `Mutex<Bool>` finished flag the tick polls; engine ->
panel is the Equatable `AudioStatsSnapshot`, read at 2 Hz by the
`InspectionTicker`. The main actor never blocks on the decode queue.

## Budget, eviction, cleanup

* **Cap**: `WorldAudioEngine.maxConcurrentSources = 8` (provisional), counting
  **positional sources only**.
* **Eviction**: starting a positional source at the cap stops the **oldest**
  playing positional source first (FIFO by start order). Predictable and
  matches how one-shot effects naturally expire; a priority scheme waits for
  game-authored data.
* **Non-positional exemption**: a music bed is outside the budget and outside
  the cell purge. It is never evicted by a burst of effects and never stopped
  because the world streamed away — it has no meaningful cell. Only an explicit
  stop, a completed fade-out, or the engine shutting down ends one.
* **Retirement**: a streamer that played its last buffer sets its finished
  flag; the next tick stops and detaches the node.
* **Looping**: `AudioPlayRequest.loops` starts a continuous source (the
  [ambience bed](/engine/world-sfx.md) is the only caller today). At end of
  file its streamer resets the decoder, rewinds to the first packet and keeps
  scheduling, so it never sets the finished flag and the tick never retires
  it; only an explicit stop, the FIFO cap or the cell purge ends it. A pass
  that decoded no PCM ends the source instead of rewinding, so a file the
  decoder cannot use can never spin the decode queue. The buffer-backed test
  seam expresses the same request through `AVAudioPlayerNode`'s own `.loops`
  scheduling option.
* **Cell unload**: each positional source records the exterior cell of its
  position; the tick stops sources more than `cellPurgeRadius = 3` Chebyshev
  rings from the listener's cell (one ring beyond the streamer's default 5x5
  residency).

## Gain ramps (the crossfade primitive)

Every source carries a **fade gain** in [0, 1], multiplied into its node volume
on top of the per-source gain. `GainFade` (`WorldAudioEngineFades.swift`) is the
ramp: a start gain, a target, a duration in seconds, and elapsed time.

* **Time source**: ramps advance only from an explicit `deltaTime` handed to
  `advanceFades(deltaTime:)` by `tick(listenerCell:deltaTime:)`. No `Date`, no
  `DispatchTime`. The renderer supplies the delta from its paused-aware
  `FrameSimClock` and skips the tick entirely while `worldSimPaused`, so a
  crossfade freezes in menu mode and never jumps on resume. A zero or negative
  delta advances nothing.
* **Curve**: linear in amplitude (not decibels). Simple, deterministic and
  adequate at music crossfade lengths; only `GainFade.currentGain` would change
  if an equal-power curve is ever wanted.
* **Retargeting**: a second fade requested mid-ramp replaces the first and
  starts from the gain the source is at right now, so the audible level never
  jumps. A duration of zero (or less) applies the target immediately.
* **Fade out and stop**: `fadeOutAndStopSource(id:overSeconds:)` ramps to
  silence and retires the source when the ramp completes, so a departing track
  cleans itself up. With duration zero it stops on the call.
* **Completion tolerance**: a ramp within `GainFade.completionEpsilon` (1 ms) of
  its duration counts as done and snaps to the target, because accumulating
  frame deltas in `Float` never sums exactly (60 additions of 1/60 miss 1).
  Without it a fade-out could hover just above silence and never retire.
* **Volume interaction**: the fade is folded into the same node-volume product
  `applyVolumesToSources()` writes, so moving a category or master slider
  mid-crossfade re-applies the ramp rather than stomping it.
* **Engine stop**: fades live on the source, so disabling the engine (which
  stops every source) discards them with the sources themselves.

## Decode policy (xWMA -> WMADecoder)

Vanilla `.xwm` carries `cbSize == 0`, so the container hands the decoder empty
extradata, while ffmpeg's WMAv2 decoder wants stream flags from extradata.
`AudioCodecParameters(xwm:)` applies the policy the parser deliberately does
not own: empty extradata is replaced with the six-byte block ffmpeg's own xWMA
demuxer synthesizes (byte 4 = 31, others zero; `libavformat/xwma.c`).
Verified against the install 2026-07-25 by the decode column of
`openskycli audio sweep`: all 269 vanilla files decode, each to exactly the
frame count its `dpds` table declares (0 mismatches, 0 failures).

## Attenuation defaults (provisional)

`ProvisionalAttenuation`: inverse model, reference distance 2 m, maximum
distance 60 m (~one exterior cell), rolloff 1. Named provisional because the
game-authored values arrive in M9.2 from `SNDR`/`SDSC`; these exist only to
make the verification surface audibly distance-dependent.

The category list (`AudioCategory`: music, effects, ambience) is equally
provisional — 9.2.1 derives the real taxonomy from the game's records and
renames this set.

## World > Audio surface

Sidebar path for acceptance: **World > Audio** (`Destination-audio`).
`AudioPanelViewController` composes two sections:

* **Output** (`PanelSection-audioOutput`): `AudioEnabledControl` checkbox,
  `AudioMasterVolumeControl` slider, `AudioMusicVolumeControl`,
  `AudioEffectsVolumeControl`, `AudioAmbienceVolumeControl`, and per category a
  mute checkbox and a solo checkbox — `AudioMusicMuteControl`,
  `AudioEffectsMuteControl`, `AudioAmbienceMuteControl`,
  `AudioMusicSoloControl`, `AudioEffectsSoloControl`,
  `AudioAmbienceSoloControl`. Readout `AudioStatsLabel`:

  ```text
  Audio: running
  Output: 48000 Hz, 2 ch
  Mute: Music, Effects  Solo: Ambience
  ```

  The last line is always present (it reads `Mute: none  Solo: none` at
  defaults) and lists muted categories by display name, comma separated. Solo
  is a checkbox rather than a radio group because clicking the category that is
  already soloed clears solo, which a radio group cannot express; picking a
  second category moves the solo. A muted or soloed category counts as an
  override, so `Destination-audio-OverrideIndicator` lights up and the
  destination reset clears both.
* **Sources** (`PanelSection-audioSources`): `AudioFileControl` popup listing
  the install's `.xwm` paths, `AudioPlaySelectedControl`,
  `AudioStopAllControl`, readout `AudioSourcesStatsLabel` (live source list —
  file, category, world position, listener distance in meters, effective
  gain — plus the cap and any trigger failure).

The trigger places the source 700 units (~10 m) straight ahead of the camera
under the `effects` category, so turning or strafing immediately pans it.
Ids are pinned in `AudioPanelTests` and `DestinationRegistryTests`.

## Per-frame cost and the frame budget

The audio subsystem's only main-thread per-frame work is
`Renderer.updateAudio(deltaTime:)`: push the camera pose into the environment
node, run `WorldAudioEngine.tick` (advance gain ramps, retire finished sources,
purge sources outside `cellPurgeRadius`), then tick the music director. Decode
never runs here — it lives on `decodeQueue` — and the AVFAudio render thread
runs no OpenSky code, so this is the whole cost the frame pays.

The work is bounded by `maxConcurrentSources = 8`: a handful of scalar updates
per source with no allocation, no I/O and no decode. That is why the budget sits
an order of magnitude below the animation gate rather than beside it.

* **Metric**: `Renderer.lastAudioUpdateMS`, the wall time of one
  `updateAudio(deltaTime:)` call, sampled per frame into
  `OffscreenBenchResult.audioUpdateMS` next to the animation and shadow samples.
  A frame that does no audio work (menu-mode pause, or no engine attached)
  records exactly zero; with no engine attached the guard returns before the
  clock is read, so the instrumentation costs one optional test.
* **Accessors**: `audioUpdateAverageMS` and `audioUpdatePercentileMS(_:)`,
  mirroring `animationAverageMS` / `animationPercentileMS(_:)`.
* **Gate**: `CellStreamingFlyBenchmarkConfiguration.audioUpdateBudgetMS`.
  Average **and** p95 must both stay within it or the fly benchmark throws
  `CellStreamingFlyBenchmarkError.audioUpdateExceeded`; the walk path enforces
  the same number in `BenchCommand`.
* **Budget**: **0.5 ms**, about 1.5% of the 33.33 ms frame at 30 fps. Override
  with `bench --audio-budget-ms`.

Measured 2026-07-26 on `bench --walk-path --size 640x360` (Debug build, 814
active physics frames, engine attached and ticking every frame, no live
sources): **avg 0.005 ms, p95 0.014 ms, max 0.028 ms**. That is the fixed
floor — the listener push plus an empty tick — and it sits roughly 35x under
the p95 gate. The remaining cost scales with the number of live sources, which
the FIFO cap holds at 8, so the 0.5 ms ceiling is reasoned headroom over a
measured floor rather than a measurement of a full source set.

Both `bench --fly-path` and `bench --walk-path` attach a (disabled) world audio
engine so the tick really runs, and print an `audio update:` line with avg, p95,
max and budget. `make probe` greps for that line on both paths.

## Verification

* `AudioSpaceTests` — conversion table above.
* `WorldAudioEngineTests` — offline manual rendering (no device, no audible
  playback): left/right channel balance for known poses, distance
  attenuation, the volume product (category 0.25 renders ~0.25x RMS),
  master-zero silence, FIFO cap eviction, cell purge, snapshot contents.
* `WorldAudioEngineMuteSoloTests` — offline manual rendering again: a muted
  category renders silence while another category still sounds, a solo silences
  the others and clearing it restores them, a soloed but muted category stays
  silent, unmuting restores the prior category volume, and a source started
  while its category is muted comes up at zero node volume.
* `WorldAudioEngineNonPositionalTests` — submix routing, stereo material, the
  category factor applied once, and both exemptions (purge, FIFO budget).
* `WorldAudioEngineFadeTests` — ramp arithmetic, fade-out-and-stop retirement,
  retargeting mid-ramp, a two-source crossfade, tick-driven advance with a
  zero delta freezing it, and the regression that a slider move mid-fade does
  not stomp the ramp.
* `AudioSourceStreamerTests` — mono downmix + interleaved-to-planar packing.
* `AudioCodecParametersXWMTests` — extradata substitution.
* `AudioPanelTests`, `DestinationRegistryTests`, `AppSidebarModelTests` —
  panel geometry, id contract, registry wiring.
* `M9AcceptanceTests` — the milestone gate driven through the app shell with no
  game data: select `Destination-audio`, enable the engine, mute one category
  and solo another, inspect the source list, trigger the picked file, force a
  playlist, and switch the SFX toggle, reading every result back out of
  `AudioStatsLabel`, `AudioSourcesStatsLabel`, `AudioSfxStatsLabel` and
  `AudioMusicStatsLabel`.
* `M9AudioAcceptanceRealDataTests` (env-gated, `make realtest`) — the same gate
  against the user's install: the route exterior cell's regions resolve to an
  ambient bed, its precedence chain resolves to a playlist whose first track is
  really in the archives, the interior cell's acoustic space resolves, and the
  route door's base yields open and close sound descriptors that resolve to
  files. Report in gitignored `logs/m9-audio-acceptance.log`; no audible
  assertion, because the vanilla effect and ambience files are `.wav`.
* `openskycli audio sweep` (gated in `make probe`) — frames **and decodes**
  the full vanilla corpus, streaming, asserting zero failures and reporting
  frame-count mismatches against `dpds`.
* Audible acceptance is a human step (app launches are visible): open
  **World > Audio**, tick `Enabled`, pick any `music\...` file, press `Play`,
  then turn (mouse-look) and strafe (A/D) — the sound must pan between ears
  as the source passes the view axis and fade with distance as you fly away.
  For the M9 gate the same person also mutes `Effects` and confirms the
  triggered sound goes silent while music keeps playing, solos `Music` and
  confirms everything else drops out, then clears both from the sidebar's reset
  and confirms the mix returns.

Sound effects in the vanilla install are `.wav` (5,978 entries) and voice is
`.fuz`; neither goes through this path yet. The `.xwm` corpus is music, so the
positional acceptance uses a music file as the positional test signal until a
PCM `.wav` reader lands.

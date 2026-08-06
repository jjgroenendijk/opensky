---
type: Subsystem
title: World audio playback
description: AVAudioEngine graph with 3D positional sources, non-positional submix
  playback, gain ramps, streaming WMA decode, vanilla category volumes with mute and
  solo, source budget, the per-frame audio budget, and the World > Audio surface.
tags: [engine, audio, playback, spatial]
timestamp: 2026-08-01T00:00:00Z
---

# World audio playback

Milestone 9.1.3: the runtime that turns a decoded `.xwm` payload into an
audible, positioned sound, plus the sidebar surface that verifies it without
the CLI. Consumes the [xWMA container parser](/formats/xwm.md) and the
[vendored ffmpeg WMA decoder](/decisions/ffmpeg-audio.md). Implementation:
`opensky/Engine/Audio/WorldAudioEngine.swift` (graph, volumes),
`WorldAudioEngineSources.swift` (source lifecycle),
`WorldAudioEngineFades.swift` (gain ramps),
`WorldAudioEngineSnapshot.swift` (published UI state),
`AudioSourceStreamer.swift` (streaming decode), `AudioSpace.swift` (coordinate
conversion), `AudioCategory.swift` (vanilla menu categories),
`AudioCodecParametersXWM.swift` (extradata policy), and
`opensky/Engine/Rendering/RendererAudio.swift` (the per-frame tick).

## Graph

One `AVAudioEngine` per app, owned by `GameViewController`, created on first
enable and handed to the renderer for the per-frame tick:

```text
positional AVAudioPlayerNode (mono, one per source)
    --> AVAudioEnvironmentNode --> main mixer --> output device
non-positional AVAudioPlayerNode (stereo, one per source)
    --> category submix AVAudioMixerNode (effects/voice/music/footsteps) --->--/
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
* **Non-positional exemption**: music and ambience beds are outside the budget
  and outside the cell purge. They are never evicted by a burst of effects and
  never stopped because the world streamed away — they have no meaningful cell.
  Only an explicit stop, a completed fade-out, an unusable stream, or the engine
  shutting down ends one.
* **Retirement**: a streamer that played its last buffer sets its finished
  flag; the next tick stops and detaches the node.
* **Looping**: `AudioPlayRequest.loops` starts a continuous source (including an
  [ambience bed](/engine/world-sfx.md)). At end of
  file its streamer resets the decoder, rewinds to the first packet and keeps
  scheduling, so it never sets the finished flag and the tick never retires
  it; only the cleanup rules for its routing path end it. A pass
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

## Decode policy (RIFF/WAVE -> PCM buffer)

Sound effects are not `.xwm`. Music and voice are; every effect in the install — all 5,978
of them — is a plain RIFF/WAVE file of uncompressed linear PCM. Until issue #352 the
engine could only play `.xwm`, so the door and activator SFX the world sound director
resolved were reaching a player that had no reader for them.

`WorldAudioEngine.playPositional(fileData:)` and its non-positional twin now peek at the
RIFF form type at byte 8 and pick a path: `XWMA` streams through `AudioSourceStreamer` as
before, `WAVE` is read whole into one `AVAudioPCMBuffer` by
[`WAVFile`](/formats/wav.md) and scheduled once. An effect is a fraction of a second — a
footstep file is around 26 KB — so streaming it would add a decode-queue hop and a
three-buffer lookahead for nothing. Buffer-backed one-shots retire themselves through the
scheduling completion handler, so `retireFinishedSources` reclaims them the same frame
they finish rather than leaving them for FIFO eviction.

## Attenuation defaults (provisional)

`ProvisionalAttenuation`: inverse model, reference distance 2 m, maximum
distance 60 m (~one exterior cell), rolloff 1. Named provisional because the
game-authored values arrive in M9.2 from `SNDR`/`SDSC`; these exist only to
make the verification surface audibly distance-dependent.

`AudioCategory` is the four vanilla [SNCT](/formats/sound.md) nodes flagged for menu
display: Effects, Voice, Music, and Footsteps. The main mixer remains the master stage.
World sounds follow `SNDR.GNAM -> SNCT.PNAM` to one of those nodes; unresolved or malformed
metadata falls back to Effects. Music playlists author their own Music route.

## Footstep director (issue #352)

The player's footsteps are played by `WorldAudioFootstepDirector`, the third director
beside the SFX and music ones. It contains no step timer, and that is the design rather
than an omission: the vanilla locomotion clips carry their own footstep triggers —
`0_master.hkx` declares `FootLeft` and `FootRight` as the first two of its 1,217 events —
so the behavior graph already says when a foot lands, at the phase the animation actually
plants it. A cadence derived from speed would drift against the animation the player is
watching. See [terrain walk mode](/engine/walk-mode.md) for the event source.

The route, once per frame:

1. `LocomotionBridge` queues the third-person graph's fired events as each fixed step runs
   (`LocomotionGraphEventQueue`). Only the third-person graph feeds it: both graphs run
   the same locomotion clips and fire the same triggers, so draining both would play every
   footstep twice.
2. `Renderer.updateAudio` drains the queue and hands the names to the director with the
   current gait and the capsule's feet position. Draining happens even outside walk mode
   and with no director attached, so a queue nobody is listening to cannot flush all at
   once when audio is switched on. The whole tick is skipped while the world sim is
   paused, and a paused frame plans no step and fires nothing, so the two agree.
3. The director offers each name to the current gait's footstep list and plays whatever
   resolves. Names the list has no tag for — the graph fires plenty, from combat to
   magic — cost one string comparison and are dropped.

The feet position is not the only thing the tick carries: `WalkController.groundMaterial`
rides along with it (issue #358), and the impact table is keyed by exactly that. Snow, wood,
grass and gravel select different `IPCT` records and therefore different sounds. The
director keeps the last reported material for the readout and lets the panel pin one in its
place, so a surface can be heard deliberately rather than by walking to it.

Footsteps are positional and placed at the feet, not at the listener, which is what makes
third person sound right. The set the player walks with comes from `ARMA.SNDD` on the
armature occupying the feet slot of the assembled body, falling back to
`DefaultFootstepSet`; worn parts precede skin parts in a resolved visual, so boots outrank
the bare foot they cover without the director ranking them. Record layouts and the chain
from tag to sound file are in [footstep records](/formats/footstep.md); how a surface names
its material is in [material types](/formats/material-type.md).

## World > Audio surface

Sidebar path for acceptance: **World > Audio** (`Destination-audio`).
`AudioPanelViewController` composes five sections. The two this page owns are
below, plus **Footsteps** (`PanelSection-audioFootsteps`); **SFX & Ambience**
(`PanelSection-audioSfx`) is documented in
[world SFX + ambience](/engine/world-sfx.md) and **Music**
(`PanelSection-audioMusic`) in [music playlists](/engine/music.md):

* **Output** (`PanelSection-audioOutput`): `AudioEnabledControl` checkbox,
  `AudioMasterVolumeControl` slider, `AudioEffectsVolumeControl`,
  `AudioVoiceVolumeControl`, `AudioMusicVolumeControl`,
  `AudioFootstepsVolumeControl`, and per category a mute checkbox and a solo
  checkbox — the corresponding `Audio<Category>MuteControl` and
  `Audio<Category>SoloControl` families. Readout `AudioStatsLabel`:

  ```text
  Audio: running
  Output: 48000 Hz, 2 ch
  Mute: Effects, Music  Solo: Voice
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

* **Footsteps** (`PanelSection-audioFootsteps`): `AudioFootstepsEnabledControl`
  checkbox, `AudioFootstepTagControl` popup listing the tags the current
  footstep set answers to *for the gait the player is in*,
  `AudioFootstepMaterialControl` popup, `AudioPlayFootstepControl`, readout
  `AudioFootstepsStatsLabel`:

  ```text
  Set: FSTBarefootFootstepSet
  Material: MaterialSnow
  Tags: FootScuffRight, FootScuffLeft, JumpUp, JumpDown, FootLeft, FootRight
  Routed 24, played 24
  Last: FootLeft: sound\fx\fst\npc\snow\walk\l\fst_npc_snow_walk_01.wav
  ```

  The tag picker is rebuilt on every sync because the gait changes as the player
  moves, and a selection that survives the rebuild is kept. Routed and played
  are reported separately: they differ by the tags the set has no footstep for,
  which is normal vanilla data rather than a fault. The play button fires one
  footstep at the player's feet without walking, so the whole chain — set, tag,
  material, impact, sound file, positional source — is verifiable standing still.

  The material picker's first entry is **Ground contact**, the default: the
  surface the walk controller reports underfoot. Picking a MATT instead pins it,
  the readout appends `(forced)`, and both the routed events and the play button
  resolve against it — which is how a user hears snow while standing on stone.
  A pinned material counts as an override, so the section's reset clears it.

The trigger places the source 700 units (~10 m) straight ahead of the camera
under the `effects` category, so turning or strafing immediately pans it.
Ids are pinned in `AudioPanelTests`, `AudioFootstepsPanelTests` and
`DestinationRegistryTests`.

### Acceptance record

The M9 milestone gate (issue #157) covers the whole destination, not one
section, so its record lives here rather than on the SFX or music page. It is
the record required by the
[sidebar verification convention](/tools/sidebar-acceptance.md), also carried as
one row in that page's ledger:

```text
Milestone: M9.2.4 (M9 overall acceptance)
Sidebar path: World > Audio > Output, > Sources, > Music, > SFX & Ambience
Destination id: Destination-audio
Controls exercised: AudioEnabledControl, the generated Audio<Category>MuteControl
  and Audio<Category>SoloControl families (AudioEffectsMuteControl and
  AudioMusicSoloControl are the two the gate clicks), AudioFileControl,
  AudioPlaySelectedControl, AudioStopAllControl, AudioMusicTypeControl,
  AudioStopMusicControl, AudioSfxEnabledControl, AudioStopAmbienceControl
Readout: AudioStatsLabel, AudioSourcesStatsLabel, AudioMusicStatsLabel,
  AudioSfxStatsLabel, plus the Destination-audio-OverrideIndicator dot
Deterministic tests: M9AcceptanceTests, WorldAudioTransitionAcceptanceTests,
  M9AudioAcceptanceRealDataTests, AudioPanelTests, AudioPanelMuteSoloTests,
  WorldAudioEngineMuteSoloTests, DestinationRegistryTests, AppSidebarModelTests,
  MusicRecordStoreTests, WorldMusicDirectorTests, CellStreamingFlyPathTests
Local A/B (optional, never committed): none
```

The two mute and solo ids are generated at runtime as
`"Audio\(category.identifierFragment)MuteControl"` and `...SoloControl` in
`opensky/App/Shell/Sections/AudioOutputSection.swift`, so grepping for the full id
finds nothing; `M9AcceptanceTests` reaches them as
`outputSection.muteControls[.effects]` and `soloControls[.music]`, which is why
they are named as a family here. `CellStreamingFlyPathTests` is listed because
the gate's "frame budget kept" clause is the audio-update budget above, and
those cases are what enforce it. No A/B capture applies: everything this
milestone adds is audible rather than visible, so a rendered frame would prove
nothing.

`M9AcceptanceTests` asserts these readout substrings verbatim: `Audio:
disabled`, `Audio: running`, `Output: 44100 Hz, 2 ch`,
`Mute: Effects  Solo: Music` and `Mute: none  Solo: none` on `AudioStatsLabel`;
`Sources: 2 / 8`, `Sources: 1 / 8`,
`doorwoodopen.xwm [effects] 700, 0, 0 | 10.0 m | gain 1.00` and
`wind.xwm [effects] 0, 0, 0 | 0.0 m | gain 0.50` on `AudioSourcesStatsLabel`,
with no `Play failed` line; `State: town`,
`Music: MUSTownWhiterun — music\MUSTownWhiterun.xwm` and `Music: none` on
`AudioMusicStatsLabel`, with no `Music error` line; and
`SFX: sound\fx\dor\doorwoodopen.xwm`, `Ambience: 0x0001AABB` and
`Ambience: none` on `AudioSfxStatsLabel`. The Music picker's first entry is
pinned to `AudioMusicSection.automaticTitle` (`None (automatic)`). The sample
rate, the file names and the FormID are invented for the test; no game data is
read.

What the record does **not** claim is that anyone has heard it. The
deterministic suites prove the control-to-provider-to-readout path and the
record resolution; the audible half is the human step at the end of this page,
of [world SFX + ambience](/engine/world-sfx.md) and of
[music playlists](/engine/music.md), and it has not been performed.

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

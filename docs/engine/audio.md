---
type: Subsystem
title: World audio playback
description: AVAudioEngine graph with 3D positional sources, streaming WMA decode,
  provisional category volumes, source budget, and the World > Audio surface.
tags: [engine, audio, playback, spatial]
timestamp: 2026-07-25T00:00:00Z
---

# World audio playback

Milestone 9.1.3: the runtime that turns a decoded `.xwm` payload into an
audible, positioned sound, plus the sidebar surface that verifies it without
the CLI. Consumes the [xWMA container parser](/formats/xwm.md) and the
[vendored ffmpeg WMA decoder](/decisions/ffmpeg-audio.md). Implementation:
`opensky/Audio/WorldAudioEngine.swift` (graph, volumes),
`WorldAudioEngineSources.swift` (source lifecycle),
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
category submix AVAudioMixerNode (music/effects/ambience)
    ------------------------------->--/
```

* The environment node does the 3D mixing. Its inputs must be **mono** — it
  passes stereo through without spatializing — so streamed stereo sources are
  downmixed (`AudioSourceStreamer.monoDownmix`, channel average).
* Per-source rendering algorithm is `.equalPowerPanning`: deterministic and
  cheap, which is what the offline-render tests need. HRTF selection is a
  later decision alongside the M9.2 attenuation data.
* Category submixes exist for future non-positional beds (music, ambience
  loops). A positional source cannot route through one — each source needs its
  own environment-node input — so its category volume is applied at its player
  node instead. Both paths use the same stored per-category volume, so they
  cannot disagree.
* Volumes multiply as: **effective gain = master x category x source**. Master
  is `mainMixerNode.outputVolume`; category x source is the player node's
  `volume`. Distance attenuation applies after all three.
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

* **Cap**: `WorldAudioEngine.maxConcurrentSources = 8` (provisional).
* **Eviction**: starting a source at the cap stops the **oldest** playing
  source first (FIFO by start order). Predictable and matches how one-shot
  effects naturally expire; a priority scheme waits for game-authored data.
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
* **Cell unload**: each source records the exterior cell of its position;
  the tick stops sources more than `cellPurgeRadius = 3` Chebyshev rings from
  the listener's cell (one ring beyond the streamer's default 5x5 residency).

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
  `AudioEffectsVolumeControl`, `AudioAmbienceVolumeControl`, readout
  `AudioStatsLabel` (running state + output device format or failure reason).
* **Sources** (`PanelSection-audioSources`): `AudioFileControl` popup listing
  the install's `.xwm` paths, `AudioPlaySelectedControl`,
  `AudioStopAllControl`, readout `AudioSourcesStatsLabel` (live source list —
  file, category, world position, listener distance in meters, effective
  gain — plus the cap and any trigger failure).

The trigger places the source 700 units (~10 m) straight ahead of the camera
under the `effects` category, so turning or strafing immediately pans it.
Ids are pinned in `AudioPanelTests` and `DestinationRegistryTests`.

## Verification

* `AudioSpaceTests` — conversion table above.
* `WorldAudioEngineTests` — offline manual rendering (no device, no audible
  playback): left/right channel balance for known poses, distance
  attenuation, the volume product (category 0.25 renders ~0.25x RMS),
  master-zero silence, FIFO cap eviction, cell purge, snapshot contents.
* `AudioSourceStreamerTests` — mono downmix + interleaved-to-planar packing.
* `AudioCodecParametersXWMTests` — extradata substitution.
* `AudioPanelTests`, `DestinationRegistryTests`, `AppSidebarModelTests` —
  panel geometry, id contract, registry wiring.
* `openskycli audio sweep` (gated in `make probe`) — frames **and decodes**
  the full vanilla corpus, streaming, asserting zero failures and reporting
  frame-count mismatches against `dpds`.
* Audible acceptance is a human step (app launches are visible): open
  **World > Audio**, tick `Enabled`, pick any `music\...` file, press `Play`,
  then turn (mouse-look) and strafe (A/D) — the sound must pan between ears
  as the source passes the view axis and fade with distance as you fly away.

Sound effects in the vanilla install are `.wav` (5,978 entries) and voice is
`.fuz`; neither goes through this path yet. The `.xwm` corpus is music, so the
positional acceptance uses a music file as the positional test signal until a
PCM `.wav` reader lands.

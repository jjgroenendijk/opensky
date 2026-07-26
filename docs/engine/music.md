---
type: Subsystem
title: Music playlists
description: MUSC/MUST playlist selection, the exploration/town/interior states,
  and the crossfading music director that owns the non-positional music sources.
tags: [engine, audio, music, playlists]
timestamp: 2026-07-26T00:00:00Z
---

# Music playlists

Milestone 9.2.3 (issue #156): turn the [decoded music records](/formats/music.md)
into playing music that follows the streamed world. Implementation:
`opensky/Audio/MusicCatalog.swift` (selection, pure value logic),
`opensky/Audio/WorldMusicDirector.swift` (runtime state machine),
`opensky/World/CellStreamerMusic.swift` (context emission), and the
non-positional playback plus gain ramps described in
[world audio playback](/engine/audio.md).

The split mirrors [world SFX + ambience](/engine/world-sfx.md) deliberately:
one engine-free resolver that a unit test can drive without an audio device, and
one main-actor director that owns source lifetime.

## Selection precedence

`MusicSelection.resolve` walks three links, most specific first, and takes the
first one that names a MUSC the store actually holds:

```text
CELL.XCMO  ->  REGN.RDMO (first resolvable among the cell's XCLR regions)
           ->  WRLD.ZNAM
```

A link that names a missing record is skipped rather than treated as "no music",
so a dangling override in a mod cannot silence the world. Regions are consulted
in the cell's authored XCLR order, which makes the choice reproducible when two
overlapping regions both carry an RDMO. With nothing selectable — no music
store, no link, or a playlist whose every track is unplayable — the result is a
silent selection, which the director treats as "stop playing".

The streamer supplies the inputs. `CellStreamer.emitMusicContextIfNeeded()`
builds a `MusicKey` from the center cell and fires `onMusicContextChanged` only
when the key changes, so a steady-state frame costs one comparison. It is called
from the same two sites as the ambience emission: the per-frame `update()`
(exterior recenter) and `apply(transition:)` (interior enter/exit, which also
calls `invalidateMusicContext()` first so a re-entered interior re-emits).

## The three states

The milestone names exploration, town and interior. Only one of those is
authored anywhere in the records, so the derivation is explicit:

| State | Derived from | Limits |
| --- | --- | --- |
| `interior` | The context is interior (the streamer holds an interior scene). | Wins over everything: an interior whose playlist is a town one still reads as `interior`. |
| `town` | Exterior whose selected MUSC editor id starts with `MUSTown` (case-insensitive). | A naming convention, not data. A record renamed by a mod, or one whose EDID is absent, reads as `exploration`. Interior town music (`MUSTownInterior...`) never reaches this branch. |
| `exploration` | Every other exterior, including one with no playlist. | The catch-all; it is not evidence that an exploration playlist was authored. |

There is no combat, dungeon or special state: those exist in the vanilla data as
further `MUSC` records (`MUSCombat...`, `MUSDungeon...`) but are triggered by
game systems OpenSky does not have yet, so inventing a state for them would be a
guess. When a combat system exists it selects a MUSC directly and the state enum
grows a case; the precedence chain above does not change.

## Playlists and flags

The winning MUSC contributes an ordered list of playable tracks:

* **Palette expansion.** A MUST whose CNAM is the palette tag carries `SNAM`
  children instead of an `ANAM` file, so it is a nested playlist.
  `MusicRecordStore.resolve` expands one level (MUSC -> MUST); the catalog
  expands the rest, bounded by `MusicSelection.maximumPaletteDepth` (4) and by a
  visited set, so a palette that references itself terminates instead of
  recursing.
* **Playable filter.** Silent tracks (no `ANAM` by definition) and tracks whose
  filename fails the `music\` path rules are dropped, preserving the order of
  the survivors. A playlist that loses every track resolves to silence; the
  winning MUSC is still reported so the readout can say which one it was.
* **Order.** `Maintain Track Order` (0x0008) keeps the authored `TNAM` order.
  Without it the order is a deterministic shuffle: Fisher-Yates over
  `SplitMix64` seeded from the context (FNV-1a over the interior flag, the
  three links and the cell identity). Hand-rolled rather than `Hasher` because
  `Hasher` is seeded per process, which would make the "random" pick differ
  between two runs of the same scene, and hand-rolled rather than
  `shuffled(using:)` so the ordering is pinned by this repository.
* **Advance policy.** `Plays One Selection` (0x0001) truncates the playlist to
  one track and ends in silence. `Cycle Tracks` (0x0004) walks the list, wrapping
  at the end. Neither flag means one track repeating for as long as the selection
  stays current, which is how a single-track MUSC behaves.

`Ducks Current Track`, `Does Not Queue` and the MUSC priority are decoded but
not acted on: they only matter once two playlists can be active at once
(combat music over exploration music), which needs the systems above.

## Crossfade contract

The crossfade is the recipe the engine primitive documents: start the incoming
source, snap it to zero gain, ramp the outgoing one to silence with
`fadeOutAndStopSource(id:overSeconds:)`, and ramp the incoming one up over the
same window. Both ramps advance only from `WorldAudioEngine.advanceFades`, which
the renderer drives with its paused-aware frame delta, so a crossfade freezes in
menu mode instead of skipping through.

The duration is the **incoming** selection's:

* `MUSC.WNAM` fade duration in seconds when authored;
* `MusicSelection.defaultCrossfadeSeconds` (2 seconds) when not;
* zero when `Abrupt Transition` (0x0002) is set — the same code path with a
  zero-length ramp, which applies both ends immediately.

Switching music off with the panel toggle stops now rather than fading: the user
asked for silence, not for a slow one. A context that resolves to silence still
fades out over the default window.

## Lifetime and the enable toggle

Music sources are non-positional, which means the engine exempts them from both
the FIFO source budget and the cell purge (see
[world audio playback](/engine/audio.md)). The director therefore owns their
lifetime completely — nothing else will ever retire a music source for it.

The director keeps the same three invariants the SFX director does:

* `desiredSelection` is remembered whether or not it is playing, so a context
  arriving while music is off is not swallowed, and re-enabling restarts it
  without waiting for the next cell change.
* One path, `applyMusicState()`, is shared by the context change, the force
  control and the enable toggle, so they cannot drift apart.
* The readout derives from live engine sources: `currentTrackName` looks the
  current id up in `engine.sources` and returns nil when it is gone, so
  `currentMusicDescription` cannot claim music that already stopped.

Playlist advance is driven from the per-frame tick. `WorldAudioEngine.tick`
retires a stream that reached the end of its file; the director's `tick` runs
after it in the same frame, notices the current id has left `engine.sources`, and
starts the next track. Sources on their way out during a crossfade are tracked
separately, so a departing track's disappearance is never mistaken for the
current track finishing. A `.repeatCurrent` selection asks the engine to loop
instead, so it never reaches the advance path.

## Failure and degradation policy

Nothing here throws at the caller. Every failure lands as silence plus a reason
in `lastMusicError`, which the panel readout shows:

* no music store (a plugin without MUSC/MUST) — silence, no error;
* an unresolvable link — the chain keeps walking;
* a playlist with no playable track — silence, the winning MUSC still named;
* a track whose file will not load — skipped for the next track in the playlist,
  bounded by the playlist length; when every track fails, silence and the last
  load failure as the reason;
* the audio engine not running — the selection is remembered and starts when it
  is.

## Threading

Main-actor only, like the rest of the audio stack. `MusicRecordStore` and
`WeatherStore` are immutable indices after construction, so the director reads
them freely; decode work stays inside the engine's decode queue. The catalog is
pure `nonisolated` value logic, which is why its tests need no engine at all.

## World > Audio > Music surface

`AudioMusicSection` (`opensky/Shell/Sections/AudioMusicSection.swift`) is the
`Music` section of the existing `World > Audio` destination, registered through
`AudioPanelViewController.makeSections()` — a fourth section beside Output,
Sources and SFX & Ambience rather than a new top-level sidebar item, per the
placement rules in [Main-app UI framework](/tools/app-ui.md). It binds to the
`AudioControlProviding` members the director exposes:

* `AudioMusicEnabledControl` — the `musicEnabled` toggle. Off fades the current
  track out; on restarts the selection the last context resolved.
* `AudioMusicTypeControl` — a picker whose first entry is `None (automatic)` and
  whose remaining entries are `selectableMusicTypeNames` (sorted MUSC editor
  ids). Choosing a playlist calls `forceMusicType(named:)`, which crossfades to
  it past the `CELL.XCMO -> REGN.RDMO -> WRLD.ZNAM` chain. Choosing
  `None (automatic)` drops the force and calls `stopMusic()`, so the next
  streamed cell resolves the playlist through the chain again. The list is empty
  until a data root loads, so the automatic entry is always present and the
  picker stays disabled until there is something to force.
* `AudioStopMusicControl` — `stopMusic()`, for A/B listening against silence.
* `AudioMusicStatsLabel` — the readout, one line per fact:
  `State: <currentMusicStateName>`, `Music: <currentMusicDescription>` (the
  `<playlist> — <path>` pair, or `none`), and `Music error: <reason>` only when
  the last force failed or `lastMusicError` is set. With no provider the label
  reads `Music: unavailable`.

The section header is `PanelSection-audioMusic`. A forced playlist is
panel-local state, because nothing on the provider records that the user forced
one; the section therefore reports itself overridden when a playlist is forced
**or** `musicEnabled` is off, while the static
`AudioMusicSection.isOverridden(provider:)` mirror the destination uses can only
judge the toggle. Resetting the destination re-enables music and calls
`stopMusic()`; the shell then resets the cached panel, which clears the forced
selection and returns the picker to `None (automatic)`.

### Acceptance record

The record required by the
[sidebar verification convention](/tools/sidebar-acceptance.md), also carried as
one row in that page's ledger:

```text
Milestone: M9.2.3
Sidebar path: World > Audio > Music
Destination id: Destination-audio
Controls exercised: AudioMusicEnabledControl, AudioMusicTypeControl,
  AudioStopMusicControl, AudioEnabledControl
Readout: AudioMusicStatsLabel
Deterministic tests: AudioPanelTests, DestinationRegistryTests,
  MusicCatalogTests, MusicCatalogPlaylistTests, WorldMusicDirectorTests,
  CellStreamerTests, MusicRecordTests, MusicRecordStoreTests
Local A/B (optional, never committed): none
```

`AudioEnabledControl` lives in the Output section of the same destination and is
listed because the music director is constructed with the world audio engine, so
nothing in this section makes a sound until the engine is running.
`CellStreamerTests` is the class name the music-context cases extend; the cases
themselves live in `openskyTests/CellStreamerMusicTests.swift`, so grepping for
the class name finds the base file, not the milestone's cases. No A/B
capture applies: the behavior this milestone adds is audible, not visible, so a
rendered frame would prove nothing (same reasoning as the M9.2.2 row).

## Verification

* `MusicCatalogTests` — the precedence chain (each link, and fall-through past a
  dangling override), the three states plus the town inference's editor-id
  limit, flag handling (`cycle`, `maintain order`, `plays one selection`),
  palette expansion including a self-referencing palette, silent/unplayable
  track filtering, the crossfade duration and its default, deterministic and
  context-dependent track order, and selection equality (the director's restart
  guard).
* `WorldMusicDirectorTests` — offline-render coverage: first start fades in,
  an equal selection does not restart, a selection change crossfades (both
  ramps checked at the halfway point and the outgoing source proven retired),
  abrupt transition cuts, playlist advance on track finish including the wrap,
  a repeating selection loops in the engine instead of advancing, the enable
  toggle round-trip restarting the remembered selection, absent store and
  unloadable files degrading silently, and the live-source-derived readout.
* `CellStreamerMusicTests` (under `CellStreamerTests`) — key diffing: emit on
  cell arrival, no re-emit in steady state, no re-emit for a musicless cell,
  `invalidateMusicContext()` forcing a re-emit, and the interior transition
  emitting an interior context.
* `AudioPanelTests` — the Music section's id contract plus round-trips through
  the provider: the picker offers `None (automatic)` ahead of the MUSC list and
  forces the chosen playlist, returning to automatic stops music instead of
  forcing again, the toggle and stop button reach the provider, the readout
  carries state, description and error, and the override/reset pair clears both
  the toggle and the forced selection.
* `DestinationRegistryTests` — a disabled music director shows as an override on
  `Destination-audio`, and the destination-level reset re-enables it.
* Fixtures are synthetic plugins built in code
  (`openskyTests/WorldMusicFixtures.swift`); the audio payload is
  `XWMFixture.file`. No extracted game file enters the repository.

Audible acceptance is a human step: enable audio, walk an exterior cell, and
listen for the exploration playlist; enter a city cell and confirm the crossfade
to its town playlist; enter an interior and confirm the state readout.

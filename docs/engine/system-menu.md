---
type: Subsystem
title: System menu
description: The Resume / Settings / Quit pause menu - its toolkit-free selector, the
  menu-stack handoff that pauses world simulation, the data-root and audio-volume
  settings placeholders, and the vanilla quest_journal.swf presentation layer behind it.
tags: [engine, ui, menu, swf, settings]
timestamp: 2026-08-01T00:00:00Z
---

# System menu

Milestone 8.5.1. The first menu OpenSky actually opens, and the first real implementer
of [menu mode](/engine/menu-mode.md)'s `MenuInputConsumer`. It carries three rows —
Resume, Settings, Quit — surfaces the two settings placeholders the milestone names,
and optionally presents itself through the vanilla `Interface\quest_journal.swf` movie.

The subsystem is deliberately split so that the menu works with no install, no
renderer, and no movie. Only the presentation layer needs any of those.

## Contents

- [The selector](#the-selector)
- [Menu-stack handoff](#menu-stack-handoff)
- [Settings placeholders](#settings-placeholders)
- [Vanilla presentation layer](#vanilla-presentation-layer)
- [Verification](#verification)
- [Limits / next](#limits--next)

| Layer | File | Target |
|---|---|---|
| Selector (rows, selection, activation) | `opensky/UI/SystemMenuModel.swift` | app + CLI |
| Vanilla movie contract | `opensky/UI/SystemMenuMovieBridge.swift` | app + CLI |
| Renderer-routed movie input | `opensky/UI/SystemMenuMovieBridgeInput.swift` | app + CLI |
| Panel seam | `opensky/SystemMenuControlProviding.swift` | app + CLI |
| Renderer + AppKit wiring | `opensky/GameViewControllerSystemMenu.swift` | app |
| Verification surface | `opensky/SystemMenuPanelViewController.swift` and `opensky/Shell/Sections/SystemMenu*.swift` | app |

## The selector

`SystemMenuModel` is a `nonisolated struct`: entry identity, the highlighted index,
the last outcome, and whether Settings has been revealed. It has no reference to a
renderer, a movie, or AppKit, so every transition is unit-tested directly
(`openskyTests/SystemMenuModelTests.swift`).

`SystemMenuEntry` is the only place an engine-side fallback row is named, so the panel and
the fallback selector cannot disagree. The vanilla movie owns its larger System-page list.
Activation returns a `SystemMenuOutcome` rather than performing the effect, because two of
the three outcomes are not state transitions the model can make:

| Row | Outcome | Who acts |
|---|---|---|
| Resume | `.resume` | the model closes itself; the host pops the menu stack |
| Settings | `.showSettings` | the model sets `settingsRevealed`; the menu stays open |
| Quit | `.quit` | the host calls `NSApplication.terminate` |

Vertical moves wrap — a three-row list is unusable without it, and the vanilla list
wraps. Horizontal moves are accepted and ignored so a one-column list still counts the
event as consumed rather than letting it fall through to world input. Cancel is
Resume: the vanilla pause menu closes on the key that opened it.

## Menu-stack handoff

Opening the menu pushes the identifier `SystemMenu` onto `MenuModeController` and
installs `GameViewController` as the stack's `inputConsumer`. That single push is what
pauses the world: `MenuModeController.onModeChange` already sets
`Renderer.worldSimPaused` and drops held camera input, wired at
`GameViewController.swift:152`. The menu therefore does not own the pause — it earns it
by being on the stack, which is exactly what [menu mode](/engine/menu-mode.md) was
built for and what had no implementer until now.

Input precedence is unchanged from what `GameMetalView` already routes:

- In gameplay, `Esc` releases mouse capture. It does not open the system menu.
- In menu mode, `GameMetalView.routeMenuKey` maps `W`/`S`/arrows to `.move`, `Return`
  to `.button(.accept)`, and `Esc` to `.button(.cancel)`, and swallows everything else.

The menu therefore has no opening keystroke. That is deliberate: the
[app-ui rules](/tools/app-ui.md) forbid dev behaviour reachable only by an unadvertised
key, and binding `Esc` to open would collide with capture release. The menu opens from
its panel; once open, the live keys drive it through the same path the panel buttons
use.

## Settings placeholders

The milestone surfaces two settings behind the Settings row. Neither is new state —
both read and write existing engine seams, so the system menu can never disagree with
the surface that already owns them.

- **Game data root** — read-only here, resolved once through
  [`GameDataLocator`](/engine/game-data-locator.md) and cached, because
  `GameDataLocator.locate()` walks the filesystem and the 2 Hz panel readout must never
  trigger that walk. Changing it stays with the Cmd+, Settings window.
- **Master volume** — writes straight through `AudioControlProviding.audioMasterVolume`,
  the same property `World > Audio > Output` drives. M9 binds the live per-category
  volumes ([audio](/engine/audio.md)) behind this master.

## Vanilla presentation layer

`startmenu.swf` is Skyrim's title screen, not the in-game pause menu. Its rows are
Continue/New/Load/Creations/Mods/Credits/Quit/Help and its 1,674-string pool has no
`$SETTINGS`. It remains a useful AS2-runtime measurement
([AS2 runtime](/engine/as2-runtime.md#startmenuswf-re-measured-at-851)), but issue #231
removed it from this subsystem.

The in-game movie is `quest_journal.swf`. Its placed `QuestJournalBase` owns three pages:
Quests, General Stats, and System. The live movie measured the System page at `PageArray[2]`
and built these category rows itself:

`$QUICKSAVE`, `$SAVE`, `$LOAD`, `$INSTALLED CONTENT`, `$SETTINGS`, `$CONTROLS`, `$HELP`,
`$QUIT`.

Activating Settings opens the movie's own category panel with `$Gameplay`, `$Display`, and
`$Audio`; its Quit panel contains `$Main Menu` and `$Desktop`. The strings remain tokens
because SWF translation substitution is not wired yet, but the hierarchy and transitions
are the original movie's.

`SystemMenuMovieBridge.prepare(runtime:)` installs the outbound trace, sound, feature-query,
and player-info handlers before `start()`. `activate(runtime:onClose:)` then calls
`SetPlatform(0)`, `InitExtensions`, `ShowMenu`, and
`SwitchPageToFront(2, true)`. The vanilla host normally seeds `TopmostPage`, `iCurrentTab`,
and focus through a tab-button group backed by engine data; OpenSky publishes the measured
System page/index pair and focuses its category list directly. The other two page faders
stop at `hide`, while System stops at its authored `forceFade` label.

When the movie is loaded, the same `MenuInputEvent` used by panel buttons and live keys is
translated to Flash key down/up events. The selected `$SETTINGS` row opens
`SystemPage.SETTINGS_CATEGORY_STATE` through its named constant and `StartState(aiState)`;
no numeric state is hardcoded. The movie's `CloseMenu` outbound call closes the engine menu
stack. If the movie is absent or rejects input, the engine selector handles the event.

Live input enters through `SystemMenuMovieBridge.send(_:renderer:)`, which batches the
bridge's runtime mutation through `Renderer.updateSWFRuntime`. That renderer seam pulls
`sceneIfChanged()` and rebuilds the planned GPU command stream before returning. Calling
`handle(_:runtime:)` directly is valid only inside another renderer-owned batch, such as a
test that sends several keys before one synchronization; using it against
`Renderer.swfRuntime` directly changes ActionScript selection state without repainting the
frame.

The pre-issue-#136 sweep measured 159 `callDepthExceeded` faults in
`quest_journal.swf`, the worst of all 53 movies. The acceptance run now reports 0 faults,
0 unimplemented opcodes, 0 unhandled invokes of 36, and 572 draws. At 1280x720, the System
page changes 361,540 pixels over empty; moving to and opening Settings changes 11,951 pixels
from that System frame. The ignored local captures contain the user's game content and are
never committed.

The renderer owns exactly one SWF layer. The system menu takes it over from the
gameplay HUD while the movie is up and hands it back on Resume — the same handoff
`Developer > UI Lab` performs when a movie is selected there
([screen-space UI](/rendering/ui.md)). The movie is off by default, so the durable
verification surface is the engine-drawn selector and the movie is an A/B on top of it.

Nothing in the movie path throws out of a control action. A missing install, an
undecodable movie, or a contract the AS2 subset cannot satisfy becomes an explanatory
string in the panel readout.

## Verification

Sidebar path: `World > System Menu`, sections `Menu` and `Settings`.

| Control | Accessibility id |
|---|---|
| Open | `SystemMenuOpenControl` |
| Resume | `SystemMenuResumeControl` |
| Up / Down / Activate | `SystemMenuUpControl`, `SystemMenuDownControl`, `SystemMenuActivateControl` |
| Vanilla menu movie | `SystemMenuMovieControl` |
| Master volume | `SystemMenuMasterVolumeControl` |
| Readouts | `SystemMenuStatsLabel`, `SystemMenuDataRootStatsLabel`, `SystemMenuSettingsStatsLabel` |

The menu readout prints the live selection with a `>` marker, the open menu-stack
identifiers, the world-sim pause state, the last activated row, and the movie's draw
count, fault count, and distinct missing-API count. An open menu or an enabled movie
both count as destination overrides, so the sidebar dot shows a paused world and Reset
returns to gameplay.

Tests: `SystemMenuModelTests` (fallback selector transitions), `SystemMenuPanelTests`
(control ids, provider round-trip, readout strings, and the pinned movie path),
`DestinationRegistryTests` (registry order and pinned ids), and
`RendererSWFInteractiveAcceptanceTests` (a synthetic key mutation repaints through the
system-menu bridge), plus
`SystemMenuAcceptanceRealDataTests` — the env-gated movie gate against the user's install.
It asserts the System and Settings rows, keyboard transition, fault/opcode/invoke tallies,
draws, and pixel deltas; its PNGs and report go to ignored `logs/`.

## Limits / next

- The panel's data-root and master-volume controls remain engine-side placeholders. The
  vanilla Settings panel is now visible and navigable, but its individual values and
  mutations still need their engine data callbacks.
- The fallback selector's Quit terminates immediately; there is no confirmation and no
  save, because there is no save system.
- SWF text still shows `$TOKEN` names. Translation substitution is not connected to runtime
  edit text yet.

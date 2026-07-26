---
type: Subsystem
title: System menu
description: The Resume / Settings / Quit pause menu - its toolkit-free selector, the
  menu-stack handoff that pauses world simulation, the data-root and audio-volume
  settings placeholders, and the vanilla startmenu.swf presentation layer behind it.
tags: [engine, ui, menu, swf, settings]
timestamp: 2026-07-26T00:00:00Z
---

# System menu

Milestone 8.5.1. The first menu OpenSky actually opens, and the first real implementer
of [menu mode](/engine/menu-mode.md)'s `MenuInputConsumer`. It carries three rows —
Resume, Settings, Quit — surfaces the two settings placeholders the milestone names,
and optionally presents itself through the vanilla `Interface\startmenu.swf` movie.

The subsystem is deliberately split so that the menu works with no install, no
renderer, and no movie. Only the presentation layer needs any of those.

| Layer | File | Target |
|---|---|---|
| Selector (rows, selection, activation) | `opensky/UI/SystemMenuModel.swift` | app + CLI |
| Vanilla movie contract | `opensky/UI/SystemMenuMovieBridge.swift` | app + CLI |
| Panel seam | `opensky/SystemMenuControlProviding.swift` | app + CLI |
| Renderer + AppKit wiring | `opensky/GameViewControllerSystemMenu.swift` | app |
| Verification surface | `opensky/SystemMenuPanelViewController.swift` and `opensky/Shell/Sections/SystemMenu*.swift` | app |

## The selector

`SystemMenuModel` is a `nonisolated struct`: entry identity, the highlighted index,
the last outcome, and whether Settings has been revealed. It has no reference to a
renderer, a movie, or AppKit, so every transition is unit-tested directly
(`openskyTests/SystemMenuModelTests.swift`).

`SystemMenuEntry` is the only place a row is named, so the panel and the movie bridge
cannot disagree about what the menu contains. Activation returns a `SystemMenuOutcome`
rather than performing the effect, because two of the three outcomes are not state
transitions the model can make:

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

`startmenu.swf` was nominated for the 8.3.3 interactive gate and rejected on measurement.
Two of the three stated blockers are gone, and the movie now comes up clean and populates
its list from the engine. The full re-measurement is in
[AS2 runtime](/engine/as2-runtime.md#startmenuswf-re-measured-at-851); the short version:

- The 35 `callDepthExceeded` faults were retired by the `super` fix (issue #136). Bring-up
  reports 0 faults and 0 unimplemented opcodes.
- `_root.CodeObj` is not a host object. The movie's own `StartMenu` constructor creates it,
  and all 16 names on it are Bethesda.net login calls, which the bridge answers with no-ops.
- The save-list contract still stands, which is why the bridge reports no saves.

`SystemMenuMovieBridge` therefore does three things: `prepare(runtime:)` registers the six
outbound sinks *before* `start()` (bring-up itself makes 24 `myLog` calls, which is why
`Renderer.startSWFRuntime` grew a `prepare` hook); `activate(runtime:version:onQuit:)`
attaches the `CodeObj` no-ops, registers the row actions, and drives `SetPlatform`,
`InitExtensions`, and `sendMenuProperties`; and `entryLabels` / `currentState` read the
result back for the panel. The invoke log ends at 0 unhandled of 36.

**The two menus are different menus.** `startmenu.swf` is Skyrim's title screen — its
1,674-string pool has no `$SETTINGS`, and the rows it builds for OpenSky are `$NEW`,
`$LOAD` (disabled), `$CREDITS`, `$QUIT`. Resume/Settings/Quit is the engine-side selector,
not this movie. The panel prints both lists so the difference stays visible rather than
being quietly conflated. Skyrim's real in-game system menu is `quest_journal.swf`.

Two measured gaps remain open. The populated `Main` state stages its content off the
viewport, so the list reads back correctly but draws nothing; and arrow keys are consumed
without effect because the focus chain handed to `StartMenu.handleInput` starts at a holder
clip that defines no `handleInput`. Both are recorded in the acceptance evidence and
tracked as issues #230 and #229; the correct movie for a true system menu is issue #231.

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

Tests: `SystemMenuModelTests` (selector transitions), `SystemMenuPanelTests` (control
ids, provider round-trip, readout strings), `DestinationRegistryTests` (registry order
and pinned ids), and `SystemMenuAcceptanceRealDataTests` — the env-gated re-measurement
of the movie against the user's install, whose PNGs and numbers go to ignored `logs/`.

## Limits / next

- Settings is a revealed panel section, not a second menu on the stack. A real settings
  menu is later work.
- Quit terminates immediately; there is no confirmation and no save, because there is
  no save system.
- The rows are not localized. The vanilla string tables land with the movie-driven
  presentation, not with the engine-side selector.

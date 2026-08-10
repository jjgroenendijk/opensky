---
type: Subsystem
title: Menu mode
description: Engine-owned menu-mode infrastructure - a push/pop menu stack, the
  world-vs-menu input-capture switch, and the per-menu world-sim pause policy the renderer
  gates its per-frame time advance on.
tags: [engine, ui, input, menu, simulation]
timestamp: 2026-07-30T00:00:00Z
---

# Menu mode

Todo 8.1.2. The engine plumbing that makes an open menu behave like Skyrim's: world
input stops driving the camera, world simulation freezes, and the frozen frame keeps
rendering with the screen-space UI on top. Deliberately UI-toolkit-agnostic so the
vanilla Scaleform SWF menu layer (M8.2) and the HUD (M8.2+) drive the same stack
without the engine knowing any concrete menu type. This is not AppKit menus and not a
menu UI. Two things open the stack today: the `Developer > UI Lab` menu-mode preview
(M8.1.4), which pushes named placeholders and attaches no consumer, and the
[system menu](/engine/system-menu.md) (M8.5.1), the first real `MenuInputConsumer`.

Three parts, split by layer so the logic stays AppKit-free and unit-tested:

- `opensky/Engine/UI/MenuStack.swift` — pure value-type push/pop stack of menu identifiers.
- `opensky/Engine/UI/MenuMode.swift` — `MenuModeController` (the single source of truth) plus
  the `MenuInputConsumer` protocol, `MenuInputEvent`, and the `InputRoute` decision.
- `opensky/Engine/Rendering/FrameSimClock.swift` — pausable wall-clock frame delta the
  renderer feeds every timed subsystem.

## Menu stack

`MenuIdentifier` is an opaque, `Hashable`, string-literal-expressible name that mirrors
Scaleform's string menu identity (for example `"InventoryMenu"`, `"Console"`,
`"Dialogue Menu"`) without hardcoding any list — the engine only compares identity.

`MenuStack` is an ordered, duplicate-free stack. The top is the focused menu that
receives input first. The mode boundary is emptiness: an empty stack is gameplay mode,
a non-empty stack is menu mode (`isMenuMode`).

Decided edge cases:

- Pop on empty is a harmless no-op returning nil, so a stray close in gameplay does
  nothing.
- A duplicate push (a name already open) is rejected and returns false, because
  Scaleform opens one instance per menu name. The caller can detect the rejection
  rather than stacking two of the same menu.
- `remove(_:)` closes a menu by name regardless of position (Scaleform closes by name,
  not only the top); `removeAll()` returns straight to gameplay.

## Controller

`MenuModeController` is a reference type shared by the input view, the renderer, and
(eventually) the menu layer, all on the main thread — same no-internal-locking
threading contract as `Renderer`. It owns the one live `MenuStack` and exposes:

- `present(_:policy:)` / `dismissTop()` / `dismiss(_:)` / `dismissAll()` — stack
  operations that also fire `onModeChange(route:worldSimPaused:)` whenever either of
  those two values moves. A push or pop that changes neither does not fire it.
- `isWorldSimPaused` — true while any open menu declares `MenuWorldPolicy.pausesWorld`;
  the renderer reads it each frame.
- `currentRoute` — `.world` in gameplay, `.menu` in menu mode; the input decision.
- `routeMenuInput(_:)` — forwards a `MenuInputEvent` to the attached
  `MenuInputConsumer` in menu mode (returns true), a no-op returning false in gameplay
  so the caller falls through to world input. The event is swallowed when no consumer
  is attached yet, but menu mode still owns (captures) it, so world input never sees
  it.

### Per-menu world policy

Menu mode meant a paused world until roadmap item 17.3. The
[dialogue menu](/engine/dialogue-menu.md) is the one menu that captures input while the
world keeps running, because voice, speaker facing and lip sync all advance on the world
clock. `present(_:policy:)` therefore takes a `MenuWorldPolicy`: `pausesWorld` is the
default and what every other menu gets without saying so, and `leavesWorldRunning` is
what `"Dialogue Menu"` alone uses.

The policy is per menu rather than a flag on the controller because two menus can be open
at once: the system menu over a conversation still pauses, and closing it hands the running
world back to the dialogue underneath. A dismissed menu's policy is dropped with it, so
re-presenting the same name without a policy pauses again.

Because the route and the pause no longer move together, `onModeChange` reports both. The
app releases held world input on the *route* flip rather than on the pause — a key held
into a non-pausing menu would otherwise keep driving a camera nobody is steering.

`MenuInputEvent` is intentionally small and toolkit-free — `move(Direction)`,
`button(accept/cancel)`, `pointer(deltaX:deltaY:)` — enough for Scaleform menu
navigation without binding to AppKit or a widget tree.

## Input-capture switch

`opensky/App/GameMetalView.swift` (the only AppKit piece) asks its `MenuModeController`
before dispatching each NSEvent. In menu mode it stops feeding `CameraInputState` and
maps events to `MenuInputEvent` instead: WASD/arrows to directional moves,
Return/keypad-Enter and mouse-down to accept, Escape to cancel, pointer motion to
`pointer`. Key-up and unmapped keys are swallowed so no world key sticks. The pointer
is left free (a menu wants a visible cursor) rather than captured. On entering menu
mode the app also calls `CameraInputState.releaseAll()` so held movement keys do not
persist under the menu.

## World-sim pause

`Renderer.worldSimPaused` gates the per-frame time advance. `FrameSimClock` is the
mechanism: each timed subsystem (camera, weather, animation) owns one. `advance(to:
paused:)` returns the seconds since the previous tick, clamped to `maxDelta` (0.1 s) so
a stall never dumps a huge step. While paused it returns zero yet still moves its
reference mark to the current time — so resuming after any pause length yields a single
frame of delta, never the whole paused span. That is the no-time-jump guarantee.

In `draw(in:)` the wall-clock advances (`advanceCamera`,
`updateWorldSimFromWallClock`, `updateWeatherFromWallClock`,
`updateAnimationsFromWallClock`) all feed `worldSimPaused` into their clock; the
animation delta also drives particles and precipitation, so a zero delta freezes game
time, camera, animations, weather, particles, precipitation, and the
[Papyrus VM](/engine/papyrus-vm.md) together. The VM is the clearest case of why the
pause is a clock rather than a branch: its per-frame hook still fires on a paused frame
and simply receives a delta of zero, so nothing in the runtime has to know a menu is
open. The offscreen render path applies the same gate
to its fixed 1/30 step. The render passes themselves are untouched, so a paused frame
still encodes, presents, and draws the [screen-space UI](/rendering/ui.md) — the world
just holds still.

`GameViewController` wires it together: it owns the `MenuModeController`, gives it to
the `GameMetalView` for routing, and sets `onModeChange` to flip
`Renderer.worldSimPaused` and clear held input.

## Verification

- Device-free: `MenuStackTests` (push/pop ordering, the mode boundary, pop-on-empty and
  duplicate-push edge cases), `MenuModeControllerTests` (mode transitions fire
  `onModeChange` only on the boundary, routing decision and consumer delivery),
  `FrameSimClockTests` (first-tick zero, clamp, and the no-time-jump proof: 600 paused
  frames over 10 s then one frame of delta on resume).
- Offscreen Metal-gated (`RendererMenuModeTests`): gameplay advances the animation
  clock across frames; menu mode holds `animationTime` at zero while a frame still
  renders at the requested size; two paused frames are byte-identical and resume
  advances by exactly one 1/30 step.

## Limits / next

- `MenuInputConsumer` has an implementer as of M8.5.1: the
  [system menu](/engine/system-menu.md) installs `GameViewController` as the consumer
  when it pushes `SystemMenu` onto the stack, so `Esc`, `Return`, and the movement keys
  drive the Resume/Settings/Quit selector while the world stays paused. Text entry and
  CLIK focus navigation still arrive with the wider SWF menu layer.
- The `Developer > UI Lab` menu-mode preview (M8.1.4) opens the stack without a
  consumer: its Push menu / Pop / Clear buttons call `pushPreviewMenu()` /
  `popPreviewMenu()` / `clearPreviewMenus()` on `GameViewController`
  (`opensky/App/GameViewControllerUILab.swift`), pushing depth-derived names
  (`UILabMenu1`, `UILabMenu2`, ...) so pure push/pop use never trips the
  duplicate-name rejection. Real menus are the SWF layer (M8.2). The panel readout
  mirrors `isMenuMode`, the top menu, stack depth, and `isWorldSimPaused`
  ([screen-space UI](/rendering/ui.md), `GameViewControllerUILabTests`). Events routed
  while only a preview menu is open are still swallowed, because the preview attaches
  no consumer.

---
type: Subsystem
title: Free-fly camera
description: Free-fly camera input model + math - WASDQE + mouse-look capture, yaw/pitch
  pose, view matrix, movement speeds tuned to Skyrim scale.
tags: [engine, rendering, camera, input]
timestamp: 2026-07-17T00:00:00Z
---

# Free-fly camera

Todo 2.8. Fly through the rendered cell with keyboard + mouse. Three parts, split by
layer so the math stays AppKit-free + unit-tested:

- `opensky/Rendering/FreeFlyCamera.swift` — pure pose (position/yaw/pitch) -> view
  matrix + per-frame integration. No AppKit.
- `opensky/Rendering/CameraInputState.swift` — shared logical input state (pressed keys,
  pointer deltas, boost). AppKit-free -> testable.
- `opensky/GameMetalView.swift` — `MTKView` subclass, the only AppKit piece: NSEvents ->
  `CameraInputState`, pointer capture.

## Input model

- Movement: WASD horizontal, Q/E vertical. W forward along view direction, S back, A/D
  strafe left/right, E up (+Z), Q down. Mapped by physical key code (US ANSI `kVK_*`), not
  character -> WASD stays under the left hand on any layout.
- Look: mouse deltas (`NSEvent.deltaX/deltaY`) while captured. Pointer right -> turn right,
  pointer up -> look up. `deltaY` is positive pointer-down (top-left origin) -> negated.
- Boost: Shift (`flagsChanged`) multiplies speed while held.
- Activate: F latches one request; streamer consumes it to use nearest teleport door
  within 192 units. See [interior door transitions](/engine/interiors.md).
- Capture: click in the view grabs the pointer (`NSCursor.hide` +
  `CGAssociateMouseAndMouseCursorPosition(0)` -> raw deltas, cursor frozen in window). Esc
  or first-responder loss releases + `CameraInputState.releaseAll()` so no key sticks.
- Autorepeat: `keyDown` ignores `event.isARepeat` -> a held key is one press, not a stream.
  State is a pressed-key set drained per frame, so repeats carry nothing new anyway.

No GameController support (later milestone).

## Camera math

Pose = position (Z-up world units) + yaw + pitch (radians).

- yaw about world +Z: 0 -> +X (east), +pi/2 -> +Y (north).
- pitch elevates: + looks up, clamped to +/-89 deg so forward never aligns world up
  (that degenerates `lookAt`).
- `forward = (cos p cos y, cos p sin y, sin p)`.
- `right = (sin y, -cos y, 0)` — horizontal, so strafing stays level at any pitch. Equals
  `cross(forward, +Z)` for level forward (yaw 0 -> south, -Y).
- `viewMatrix = MatrixMath.lookAt(eye: position, target: position + forward, up: +Z)` —
  same lookAt + Z-up basis change as the rest of the renderer
  ([coordinates](/decisions/coordinates.md)).

Per frame (`FreeFlyCamera.update`): look first (movement uses the new heading), then move.
Look: `yaw -= lookRight * sensitivity`, `pitch = clamp(pitch + lookUp * sensitivity)`,
sensitivity 0.0025 rad/point. Move: combined direction
`forward*fwd + right*strafe + Z*vertical`, normalized (diagonal not faster), times
`speed * dt`.

## Speeds (Skyrim scale)

Exterior cell = 4096 units ([coordinates](/decisions/coordinates.md)). Base speed 1800
units/s -> ~2.3 s per cell (seconds, not minutes). Shift x3.5 -> ~6300 units/s. Both are
`FreeFlyCamera` constants; `crossingOneCellTakesSeconds` guards the tuning.

## Renderer wiring

`Renderer` holds a live `FreeFlyCamera`, seeded from the injected `SceneCamera`
(`init(framing:)` recovers yaw/pitch from eye -> target -> the launch view matches the 2.7
framing exactly). Optional `CameraInputState` (nil for offscreen/tests -> pose stays
static, so `RendererOffscreenTests` / `CellRenderRealDataTests` are unchanged).
`draw(in:)` calls `advanceCamera()`: real `dt` from `CACurrentMediaTime` clamped to 0.1 s
(a stall cannot teleport), `input.makeInput(dt:)` -> `camera.update`. Sun/ambient still
come from the injected `SceneCamera`; only view + camera position now come from the
free-fly pose. `GameViewController` owns the `CameraInputState`, sets it on the
`GameMetalView`, and passes it to `Renderer`.

## Verification

Camera math + input state unit-tested (`FreeFlyCameraTests`, `CameraInputStateTests`):
orientation vs conventions, pitch clamp, movement direction relative to yaw, boost, seed
reproduces the framing view. Offscreen render tests still pass (static pose = seeded
framing). Live pointer capture is AppKit runtime behavior — not exercised by units and not
GUI-verified here (app launches are user-visible); the input->state mapping that unit tests
do cover is the load-bearing logic.

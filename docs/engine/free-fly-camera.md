---
type: Subsystem
title: Free-fly camera
description: The free-fly camera's input model, its yaw and pitch math, and speeds sized to
  Skyrim's scale.
tags: [engine, rendering, camera, input]
---

# Free-fly camera

The free-fly camera flies through the world with keyboard and mouse. The code has three parts,
so the math has no AppKit and can be unit tested:

- `FreeFlyCamera`: the pose (position, yaw, pitch), the view matrix, and movement per frame.
- `CameraInputState`: the pressed keys, mouse movement, and boost.
- `GameMetalView`: the only AppKit part. It turns key and mouse events into `CameraInputState`
  and captures the pointer.

## Input

- Move: W and S forward and back along the view, A and D sideways, E up (+Z), Q down. Keys are
  read by physical key code, not by character, so WASD stays under the left hand on any keyboard
  layout.
- Look: mouse movement while the pointer is captured. Pointer right turns right, pointer up looks
  up. AppKit's `deltaY` is positive downward, so it is negated.
- Boost: hold Shift.
- Activate: F. In walk mode it uses the [interaction](/engine/interaction.md) target. Fly mode has
  no target.
- Mode: G cycles fly, [walk mode](/engine/walk-mode.md), and third person. Fly is the default. Q, E
  work only in fly mode.
- Capture: a click in the view hides the pointer and freezes it
  (`CGAssociateMouseAndMouseCursorPosition(0)`), so only raw movement arrives. Esc, or the view
  losing focus, releases it and clears all keys, so no key stays stuck.
- Key repeat is ignored. A held key is one press.

## Math

The pose is a position (Z up, game units), a yaw, and a pitch, in radians.

- Yaw turns about +Z. 0 faces +X (east). pi/2 faces +Y (north).
- Positive pitch looks up. It is clamped to +/-89 degrees, because a view straight up breaks
  `lookAt`.
- `forward = (cos p * cos y, cos p * sin y, sin p)`
- `right = (sin y, -cos y, 0)`. It is always level, so strafing stays level at any pitch.
- The view matrix is `lookAt(eye: position, target: position + forward, up: +Z)`, the same as the
  rest of the renderer ([coordinates](/decisions/coordinates.md)).

Each frame, look first, so movement uses the new heading. Then move along
`forward * f + right * s + Z * v`, normalized so a diagonal is not faster, times speed and frame
time. Mouse sensitivity is 0.0025 radians per point.

The frame time is clamped to 0.1 seconds, so a stall cannot jump the camera far.

## Speed

An exterior cell is 4096 units. The base speed is 1800 units per second, so one cell takes about
2.3 seconds. Shift multiplies it by 3.5, to about 6300 units per second.

## Start pose

The renderer starts the camera from the scene's framing camera. It works out the yaw and pitch
from the eye and target, so the first frame matches the framing view. Offscreen renders and
tests have no input, so the pose stays fixed.

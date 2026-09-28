---
type: Subsystem
title: AS2 input and events
description: How a running movie receives events, injected pointer and key input, hit testing,
  CLIK focus and menu navigation, and the tick-based timers CLIK depends on.
tags: [engine, swf, actionscript, ui, scaleform, input]
---

# AS2 input and events

This page covers how the [AS2 display runtime](/engine/as2-display-runtime.md) hears about the
world: events, input, focus, and timers.

## Events

Three ways deliver an event to a movie. The clip event census decides how much each matters: across
all 53 vanilla movies, only `construct` appears much (122 handlers in 24 movies). `load` and
`enterFrame` appear once each, and every mouse and key `CLIPACTIONS` event appears zero times.

- Handler members: `clip.onPress`, `clip.onRollOver`, `clip.onEnterFrame`. This is what vanilla uses:
  `gfx.controls.Button` sets `onPress = handleMousePress` in `configUI`, and `tweenmenu.swf` sets
  `onRollOver` and `onMouseDown` on its input rectangles. The name is looked up through the prototype
  chain, so an inherited handler works like one set on the instance. A clip with no handler is
  normal.
- `CLIPACTIONS` handlers: every record whose flags include the event runs. A `keyPress` record runs
  only for its own key. Vanilla registers no key clip handler, so key dispatch counts registrations
  and skips the tree walk when there are none.
- Broadcaster listeners: the `addListener` and `removeListener` convention `Key`, `Mouse`, `Stage`,
  and `Selection` share. A broadcast calls the message on every listener.

A new instance follows the spec's `ClipEventFlags` order: `initialize` and `construct` fire when the
clip is created, before `load`. The clip's frame 1 is built, `initialize` fires, the registered
constructor runs, then `construct` and `load`. Removal fires `unload` while the child is still
attached, so `_root` and `_parent` still resolve in the handler. `enterFrame` fires once per tick for
every clip except the root.

## Input

Input is injected, never read. There is no clock, no `NSEvent`, and no global on this path, so a
test, an offscreen render, and the app run the same code and draw the same frame. The events are:
pointer moved, pressed, released, wheel, key down (code and ASCII), and key up.

Pointer positions are in movie stage pixels, the space `Stage.width`, `Stage.height`, and `_xmouse`
use. A framebuffer pixel is converted by inverting the letterbox transform. A point in the letterbox
bars belongs to no part of the movie and is dropped.

Handling an event answers whether the movie used it, so the engine can give an unused key to the
world. False is normal.

Pointer routing:

- A move changes the hover object, sends `rollOut` to the one it left and `rollOver` to the new one.
  With the button held over the pressed object, it sends `dragOut` and `dragOver`, as Flash does.
- A press sends `press` to the object under the pointer and remembers it. A release sends `release`
  if the pointer is still over it, and `releaseOutside` if not. That is how a CLIK button cancels.
- `onMouseMove`, `onMouseDown`, and `onMouseUp` are global in Flash: every clip that defines one is
  called wherever the pointer is. Vanilla depends on this: `tweenmenu.swf` uses `onRollOver` to
  highlight and `onMouseDown` to activate, and the second would never fire if only the hit target
  heard it. The runtime keeps a weak index of clips with such handlers, updated as properties and
  prototypes change, and walks it in tree order instead of scanning every clip. The `Mouse`
  broadcaster gets the same three messages.

Key routing:

- The `Key` broadcaster hears `onKeyDown` and `onKeyUp` first, because CLIK's
  `gfx.managers.InputDelegate` registers there. A listener observes and does not consume. Vanilla
  movies register unrelated `Key` listeners (`Shared.GlobalFunc.IsKeyPressed` in `tweenmenu.swf`)
  that would otherwise swallow every key. Only `handleInput` says whether a key was used.
- Then the menu's own `handleInput`, then CLIK's `FocusHandler`, then the focused object's
  `onKeyDown` as a last resort.
- A key release goes to the broadcaster, clip events, and the focused object, but not to
  `handleInput`. A vanilla menu's `handleInput` acts on the event, not its phase, so sending both
  edges would move a selection twice and land back where it started. One press is one navigation.

## Hit testing

Hit testing walks the tree in reverse paint order and finds two things: the topmost drawn node under
the pointer, and the topmost mouse-enabled node, which gets `onPress`. It respects `_visible` (a
hidden subtree catches nothing), the matrix chain (the point is moved into each node's space), and
clip layers (a masked node is hit only where the mask is, the same `(depth, clipDepth]` rule scene
generation uses).

A clip is mouse-enabled when it has `onPress`, `onRelease`, `onReleaseOutside`, `onRollOver`,
`onRollOut`, `onDragOver`, `onDragOut`, `onMouseDown`, or `onMouseUp`, or a mouse `CLIPACTIONS`
handler. Flash sends a mouse event to a clip only when it can handle one, and CLIK sets exactly these
in `configUI`.

Hits use bounding boxes, not shapes. That matches `MovieClip.hitTest` in Flash, and every
mouse-enabled CLIK control is a rectangular button or list row. A rotated or odd-shaped control gets
a slightly large hit area.

## Focus and menu navigation

Vanilla menus navigate through CLIK: `NavigationCode` is used 1,669 times across 34 movies and
`FocusHandler` 420 times. CLIK's own path is: `InputDelegate` listens on `Key`, turns a key code into
a `gfx.ui.NavigationCode` string, wraps it in `gfx.ui.InputDetails`, and sends an `input` event that
`FocusHandler` passes down the focus path to the focused component's `handleInput`.

In `startmenu.swf`, only half that chain wakes up by itself: after bring-up `FocusHandler._instance`
exists and `InputDelegate._instance` does not, so nothing listens on `Key`. So the engine does the
missing `InputDelegate` step, with the movie's own constants: it reads `gfx.ui.NavigationCode.UP` and
the others from the movie, and builds a real `gfx.ui.InputDetails` when the movie has the class, or
a plain object with the same five fields when it does not.

Two targets, in order:

1. The menu root's `handleInput(details, pathToFocus)`. Every vanilla menu class has that
   two-argument method: `TweenMenuObj`, `StartMenu`, `gfx.controls.Button`,
   `Shared.BSScrollingList`, and `FocusHandler`. The engine finds the outermost clip that defines it,
   breadth first from the root, at most 3 levels deep. That keeps the search on menu roots: a vanilla
   menu clip is one or two levels below `_root`, and the CLIK controls that also define it are deeper
   and reached by the menu's own forwarding. This is the observed shape, not a declared contract.
2. `gfx.managers.FocusHandler.instance.handleInput`, for a movie whose focus manager is live. The
   instance is behind a getter, so reading it calls it, which also creates it.

The focus path passed to `handleInput` is the chain of clips from the handler to the focused object,
keeping only clips that define `handleInput`. It is empty when nothing has focus. The filter matters:
a vanilla menu nests its list under a plain holder clip (`startmenu.swf`: `Menu_mc`, then
`MainListHolder`, then `List_mc`), and the movie forwards down `pathToFocus[0]`. The holder defines
no `handleInput`, so an unfiltered path dropped every key.

## Timers

`setInterval`, `clearInterval`, `setTimeout`, and `clearTimeout` are required. CLIK's
`UIComponent.invalidate()` schedules its own `draw()` with `setInterval(this, "_validate", 1)`, so a
component that cannot set an interval never lays itself out, never fills its text, and never becomes
interactive.

A timer counts ticks, not milliseconds. The milliseconds are converted with the movie's own header
frame rate, never to zero ticks, and at most 3,600. A timer fires from the tick that moves playheads.
A timer set by a callback during a firing pass does not fire in that pass. Both calling forms work:
`setInterval(function, ms, ...)` and `setInterval(object, "method", ms, ...)`, the one CLIK uses. The
method name is looked up when the timer fires, so a movie can replace the method. At most 256 timers
exist, and extra ones are counted.

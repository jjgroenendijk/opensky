---
type: Subsystem
title: AS2 input and events
description: How a running movie receives events, injected pointer and key input, hit testing,
  CLIK focus and menu navigation, and the tick-based timers CLIK depends on.
tags: [engine, swf, actionscript, ui, scaleform, input]
---

# AS2 input and events

This page covers how the [AS2 display runtime](as2-display-runtime.md) hears about the
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
hidden subtree catches nothing), `_alpha`, the matrix chain (the point is moved into each node's
space), and clip layers (a masked node is hit only where the mask is, the same
`(depth, clipDepth]` rule scene generation uses).

Nothing inside a subtree drawn at alpha 0 catches the pointer. The pause menu shows why: its hidden
Quests and General Stats pages stay above the System page at alpha 0, and the faded-out Settings
category list stays above the option rows. In the game a click still reaches the System page and
the option rows.

An alpha-0 clip with a mouse handler of its own is a hit area: it catches the pointer over its
shapes, and `Mouse.getTopMostEntity()` answers it. The Tween menu needs this. Each of its four
entries has an `InputRect` clip at alpha 0 above the entry, and its `onMouseDown` opens the entry
only when `getTopMostEntity()` is that clip.

A clip is mouse-enabled when it has `onPress`, `onRelease`, `onReleaseOutside`, `onRollOver`,
`onRollOut`, `onDragOver`, `onDragOut`, `onMouseDown`, or `onMouseUp`, or a mouse `CLIPACTIONS`
handler. Flash sends a mouse event to a clip only when it can handle one, and CLIK sets exactly these
in `configUI`.

A shape is hit on its fill and stroke triangles, the ones the renderer draws, so a point in the
empty corner of an L-shaped clip misses it. A clip is hit where any visible child is hit. Text
fields, static text, and buttons use their bounding box. A mask still cuts by its bounding box.

`MovieClip.hitTest(x, y, true)` tests the shapes the same way, with `x` and `y` in stage pixels.
`hitTest(x, y)` and `hitTest(clip)` keep the bounding box, as in Flash.

## Keys the game sends

The game sends a movie key events, never navigation names. The movie's own script turns the codes
into `NavigationCode` values. The keys bound to the menu controls become these codes, whichever
device pressed them:

| Menu control | Key code |
| --- | --- |
| Up, Down, Left, Right | 38, 40, 37, 39 |
| Accept | 13 |
| Cancel | 9 |
| Page Up, Page Down | 33, 34 |

A press sends key down, and a release sends key up. A held direction repeats as key down: the first
repeat comes 0.5 seconds after the press, then one about every 0.1 seconds. While the journal is
open, the two times are 0.2 and 0.075 seconds. A key bound to a menu control is not also sent with
its own code, so one press never arrives twice.

A keyboard key that no menu control binds goes through with its own code. Of those, only Backspace,
Delete, and the arrow keys repeat when held: after 0.3 seconds, then every 0.05 seconds. A gamepad
button that no menu control binds arrives as a code from 96 to 107. That is the only sign of the
device: the event carries no field that says keyboard or gamepad.

Each mouse wheel notch is a wheel event at the cursor, with a delta of +1 up and -1 down.

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

A movie that builds its own `InputDelegate`, as `racesex_menu.swf` does, already hears the key on
`Key` and sends it down its focus path. The engine then skips both targets below, because a second
route would move a list two rows for one key press. That route reads the focus from CLIK's
`FocusHandler`, which learns it only from `Selection` listeners. So an engine bridge moves focus
through `Selection.setFocus` too, never by setting the runtime's focus alone. Otherwise
`startmenu.swf` sends each key to its menu clip with an empty focus path, and the list stays put.

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

### Who sets the focus

CLIK's `UIComponent.focused` setter reads `Selection.numFocusGroups` and
`System.capabilities.numControllers`, then calls `Selection.setFocus` once per controller. GFx adds
these fields; Flash has none of them. Without them, no CLIK control takes focus. The game does
not set the controller count, so a menu reads GFx's default of one controller, with or without a
gamepad. That controller is in focus group 0, and each focus change calls the `Selection`
listeners' `onSetFocus(old, new, 0)`.

A gamepad shows only in the platform. `SetPlatform` gets 1, PC with a gamepad, while a gamepad is
connected and the `$360 Controller` row is on, and 0 otherwise. Its second argument is always
false. The last input does not matter: a key press with a gamepad connected keeps the gamepad
art. The movie gets `SetPlatform` when it starts, and again when the first gamepad connects or
the last one goes.

CLIK's `Button` reads its `focusIndicator` member and tests it with `== null`. When it is null, the
button shows focus with its own `over` state; when it is a child clip, the child plays `show` and
`hide`. A scan of every node of all 53 vanilla movies after bring-up found no clip named
`focusIndicator`, so Flash's answer is `undefined`. The runtime answers that without counting it as
a missing name.

Four more CLIK fields get the same answer, because the movies read them before they set them:
`_listeners` (tested `== undefined`, then created), `invalidationIntervalID` (tested, then set by
`setInterval`), `inspectableGroupName` (tested `== null` and `== ""`), and `buttonRepeatInterval`
(cleared, then deleted). More names get it for the same reason, each checked in the bytecode:

- `textField` on a CLIK button with no label, such as a scroll bar's thumb, track, and arrows, and on
  a scroll target holder. Each read is tested against `null` or only passed on.
- `width` and `height` on a text field. CLIK's `Constraints` tests them against `null`, then uses
  `_width` and `_height`.
- `_selectable` and `_password` on CLIK's `TextInput`. Both are copied to the inner field before the
  component sets them.

The class preamble `if (!_global.gfx) _global.gfx = new Object()` tests each package root (`gfx`,
`Shared`, `Components`), and `UIComponent.onLoad` tests `_global.CLIK_loadCallback`. Those four
globals are not counted either.

### Gamepads

The app reads every gamepad through Apple's Game Controller framework once a frame. The menu buttons
follow the install's `interface\controls\pc\controlmap.txt`: in "Menu Mode", Accept is A (`0x1000`),
Cancel is B (`0x2000`), the D-pad is Up, Down, Left, and Right (`0x0001` to `0x0008`), and the left
stick (`0x000b`) moves too; in "Item Menus", XButton is X (`0x4000`) and YButton is Y (`0x8000`). The
codes are the XInput button masks. A gamepad press becomes the same menu event as the matching key.
A held direction repeats as the keyboard's does ([keys the game sends](#keys-the-game-sends)).

Button art comes from `SetPlatform(platform, ...)`. `Shared.ButtonChange` sets `PLATFORM_PC` to 0
and `PLATFORM_PC_GAMEPAD` to 1. The game sends 0 while no gamepad is active and 1 while one is, with
`false` as the second argument on PC. A gamepad is active when one is present and turned on in the
settings. The game sends the call when a movie loads, right after `InitExtensions`, and again to every
open menu when a gamepad connects or leaves. It does not follow the last device used: a key press
with a gamepad connected keeps 1. In the same step, a menu that shows the cursor shows it with 0 and
hides it with 1. OpenSky does the same.

### Gamepads in the world

Outside a menu a gamepad plays the game. The control map's gamepad column binds each
`Main Gameplay` row, as the keyboard column does: A activates, B opens the Tween menu, X readies
the weapon, Y jumps, the left bumper sprints, the right bumper shouts, the right trigger attacks,
the left trigger blocks, the left stick button sneaks, the right stick button switches the view,
Back waits, Start opens the journal, D-pad up and down open the favourites, and D-pad left and
right use favourites 1 and 2. A button press is the same action a key press is, through the same
locks. A trigger counts as pressed above 5 % of its travel.

Each stick has a radial dead zone: below 25 % of the travel it reads 0, and from 97 % it reads 1,
with a straight line between. A radial dead zone keeps a diagonal's direction.

The left stick moves, added to the move keys, and ends Auto-Move. The direction is free, and the
speed is a share of run speed that follows this curve, a straight line between the points:

| Push | 0 | 0.2 | 0.7 | 0.9 | 1 |
| --- | --- | --- | --- | --- | --- |
| Share of run speed | 0 | 0.1 | 0.5 | 0.9 | 1 |

So a small push walks, and there is no separate walk or run step.

The right stick turns the view. Each frame:

1. A small push on the other axis is taken away: each axis loses up to 0.15 of the other
   axis's push, and the rest is scaled back to 0 to 1.
2. The push length m becomes 0.115141 m - 0.382666 m² + 2.02865 m³ - 0.754499 m⁴. This is
   close to a cube: half a push turns at about a sixth of full speed.
3. While the stick is pushed all the way, the speed grows in a straight line to 2.5 times over
   0.92 s, at the default sensitivity.
4. The result is multiplied by the sensitivity, 0.66672 by default and 0.4445 to 1.5556 in all.
5. A full yaw turns π radians a second times that; a full pitch turns 0.5625 × 3 radians a
   second times that.

At the default sensitivity a full push turns about 121 degrees a second at first, and about 302
after the ramp. Invert Y flips the pitch.

The Gameplay row `$360 Controller` turns gamepad reading on or off; off, the game reads no gamepad,
not even in a menu. `$Vibration` turns the rumble on or off. Both take their defaults from the
install's `SkyrimPrefs.ini`, `bGamepadEnable` and `bGamePadRumble`.

With a gamepad connected, the Controls list shows the rows the file lets a gamepad remap, with
their `360_` button art, and the next gamepad button binds the chosen row. A button another row
holds swaps to that row. A remap is stored as `Gamepad|<context>|<event>`.

`openskycli game debug gamepad --count 1` reports a gamepad without one connected, and
`--press down,a` presses buttons. `state menu` shows the movie's focused clip, its frame label, the
controller count, and the platform.

With that in place, a menu movie focuses its own lists. Measured with `swf movie-probe` and
`menu system`:

| Movie | Focus the movie sets | Engine step still needed |
| --- | --- | --- |
| `racesex_menu.swf` | The active list | None |
| `quest_journal.swf`, System page | The settings list and the options list, on `StartState` | The first page and tab: their seed data is missing, so the engine focuses the category list |
| `inventorymenu.swf`, `containermenu.swf` | The category list, a few ticks after `InitExtensions` | Focus on the item list after each publish, because OpenSky changes the category itself |
| `startmenu.swf` | `Menu_mc`, where up and down move nothing | Focus on the list of the current state |
| `levelupmenu.swf` | None | Focus on the highlighted button |

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

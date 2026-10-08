---
type: Subsystem
title: AS2 display runtime
description: The clip tree ActionScript drives - the host seam, display objects, bring-up and
  timeline jumps, the property surface and its units, text, scene generation, the built-in
  classes, and what is left out on purpose.
tags: [engine, swf, actionscript, ui, scaleform]
---

# AS2 display runtime

The display runtime is the mutable clip tree behind the [AS2 runtime](/engine/as2-runtime.md). It
steps timelines and produces the draw commands the [SWF render layer](/rendering/swf-layer.md) draws.

## The host seam

Everything the interpreter cannot answer from its own objects leaves through one host protocol:
timeline commands (`ActionStop`, `ActionPlay`, `ActionGotoFrame`, `ActionGoToLabel`), numbered
display properties, target paths, path lookups, `_root`, `_parent`, `_level0`, and member reads and
writes. `ActionGetProperty` and `ActionSetProperty` take an index, but the spec does not give the
table, so the index-to-name mapping is as observed from the ActionScript property list.

Declining is normal: every method may answer nothing, and the interpreter counts a decline instead of
failing. Member lookups only ask the host for objects that carry a host payload, so ordinary misses
never reach it. The real host answers from the display tree. Its link back to the movie runtime is
weak, because the runtime owns the interpreter and the interpreter owns the host. A recording host
declines everything and logs each request, which measures a movie's demands without a display list.

## Display objects

A display object is one placed character: depth, instance name, matrix, color transform, clip depth,
visibility, and, for a clip, its timeline, playhead, and play state. Children are kept by depth and
read in rising depth, which is paint order.

Every node has an ActionScript object face. The node owns the object, and the object's host payload
points back at the node weakly. A strong pair would never be freed. The weak side also gives the
right behavior: a script that kept a removed clip sees its members turn `undefined` instead of
bringing it back.

A named instance is also a property of its parent's object. So a bare `panel` resolves from a frame
action, and `_root.panel._x` resolves through the ordinary member path. The host's child lookup is
the fallback.

Bounds are computed when asked: a leaf's character bounds, and a clip's union of its children's
transformed bounds. `_width` and `_height` are the axis-aligned size of the transformed box, so a
rotated clip is wider than its artwork, as in Flash.

## Bring-up

Bring-up runs in the order the vanilla menus need, because they are class libraries:

1. every `DoInitAction` block, in tag order, against the root clip;
2. the root's frame 1 control tags, which create characters as they are placed;
3. the root's frame 1 `DoAction` blocks.

Placing a sprite is where a movie comes alive. If the character has a linkage name
(`ExportAssets`) and a class was registered against it (`Object.registerClass`), the constructor runs
with the clip as `this`, and the class prototype becomes the clip's `__proto__`. A frame's
constructors run after all of the frame's placements, children before parents. So a constructor sees
its own children and also the siblings the same frame places after it. The order is inferred from
the race menu: its panel constructor reads the category list from a sibling clip placed later, and
the game shows that list, so the sibling must exist when the constructor runs. A clip a script
makes, with `attachMovie` or `duplicateMovieClip`, is constructed before the call returns,
because the script uses it next.
A registered class may not extend `MovieClip`, so the built-in clip methods are also reachable
through the host after the prototype chain misses. Flash resolves those natively too.

Bring-up runs once. A host hook can run before it, for engine functions a movie calls from its own
`DoInitAction` blocks.

## Advancing and jumping

One tick moves every playing clip one frame, then sends `enterFrame` and fires timers that are due.
Stepping one frame forward applies only that frame's control tags.

Any other jump rebuilds the target state from frame 1, because a display list is the sum of every
step before it and tags carry no undo. The live children are then matched against it, not replaced.
A child the target frame still places at the same depth with the same character is kept. So a clip
can attach a handler to a child, jump its own timeline, and still find the handler. `tweenmenu.swf`
does exactly that: it puts `onRollOver` and `onMouseDown` on its four input rectangles in
`InitExtensions`, then opens with a `gotoAndPlay` two frames on. Rebuilding from scratch left the
menu unclickable. Children the target frame does not place are unloaded. New depths are created.

The target frame's `DoAction` blocks run. Skipped frames' blocks do not, matching `gotoAndStop`. A
frame action that jumps its own clip comes back into this path, so this nests at most 8 deep, and
dropped blocks are counted.

`gotoAndStop` and `gotoAndPlay` take a one-based frame number or a label. `ActionGotoFrame`'s operand
is zero-based, as the spec says. An unknown label is counted and leaves the playhead alone.

## Properties

ActionScript uses pixels and degrees. The display list uses twips and matrix terms. One constant
does every conversion (20 twips per pixel), because a wrong factor moves a whole menu without any
error.

| Property | Read | Write |
| --- | --- | --- |
| `_x`, `_y` | Translation / 20 | Rounded and clamped to the `Int32` twip range |
| `_xscale`, `_yscale` | Length of the matrix basis vector x 100 | Rescales that vector |
| `_width`, `_height` | Transformed bounding box / 20 | Rescales so the box matches |
| `_rotation` | `atan2(RotateSkew0, ScaleX)` in degrees | Rebuilds the linear part, keeping both lengths |
| `_alpha` | Color transform alpha multiplier x 100 | Sets that multiplier |
| `_visible` | Node flag | Node flag. A hidden node's subtree leaves the scene |
| `_name`, `_target` | Instance name, slash path | `_name` renames and rebinds the parent's property |
| `_currentframe`, `_totalframes`, `_framesloaded` | One-based playhead, frame count | Refused |
| `_xmouse`, `_ymouse` | The injected pointer in the node's own space, in pixels | Refused |
| `_droptarget`, `_url`, `_highquality`, `_focusrect`, `_soundbuftime`, `_quality` | Fixed answers | Refused |

The last row answers instead of declining, so a runtime with no window or sound does not fill the
missing-API tally with names that will never be implemented. CLIK's `__width` and `__height` are
ordinary properties, not display properties. The host declines them, so the write reaches the
object's own table.

## Text

A field's runtime text is, in order: an explicit assignment (`field.text = "..."` or `SetText`), the
value of its `VariableName` binding, then the character's `InitialText`. Writing the field writes the
bound variable back, so a movie that reads `_root.someVar` later sees the same string. The text
reaches the renderer as an override on the scene item, and the layout code lays out that run again
([SWF render layer](/rendering/swf-layer.md)).

## Scene generation

The runtime produces the same scene command stream as the static scene builder, with the same clip
semantics and paint order. So the renderer reads one stream type and never learns whether
ActionScript is running. An idle movie produces no new scene, so it costs nothing.

At most 4,096 nodes are created, so a runaway `attachMovie` loop is counted instead of using up
memory. Every tree walk stops at depth 32.

## Built-in classes

These are Flash and Scaleform GFx built-ins with no spec behind them, rebuilt from public ActionScript
2 documentation and observed bytecode.

- `MovieClip.prototype`: `play`, `stop`, `gotoAndPlay`, `gotoAndStop`, `nextFrame`, `prevFrame`,
  `getDepth`, `getNextHighestDepth`, `getInstanceAtDepth`, `swapDepths`, `removeMovieClip`,
  `attachMovie`, `createEmptyMovieClip`, `hitTest`, `toString`, `getBounds`, `localToGlobal`,
  `globalToLocal`, and `duplicateMovieClip`.
- `TextField.prototype`: `SetText` and `SetTextHTML` (GFx additions, 595 calls across 31 vanilla
  movies), and `setTextFormat` and `getTextFormat`, which are accepted and ignored, because layout
  draws one font and color per field.
- `Stage`: a plain object. `width` and `height` come from the movie's `FrameSize`: OpenSky letterboxes
  instead of reflowing, so the stage never resizes. `visibleRect` and `safeRect` are separate objects
  covering the full frame, because OpenSky has no overscan crop or safe area. The vanilla
  `MovieClip.Lock` helper reads both to place menus. Without them every edge read zero, and the start
  menu's holder moved from `(1280, 720)` to `(0, 0)`.
- `Selection`: `setFocus` and `getFocus` round-trip a focus target. Range queries answer -1.
- `Object`, `Function` (`call`, `apply`), `Array`, `String`, `Number`, `Boolean`, `Math`,
  `ASSetPropFlags`, `isNaN`, `parseInt`, `parseFloat`, `NaN`, `Infinity`, the global `random(n)`, and
  `flash.geom.Point`. These follow ECMA-262 3rd edition section 15, as ActionScript does.
- `Key`, `Mouse`, and the timer functions ([AS2 input](/engine/as2-input.md)), and `ExternalInterface`
  and `fscommand` ([GameDelegate bridge](/engine/as2-game-delegate.md)).

`Math.random` draws from a seeded xorshift64\* generator owned by the runtime, so a menu that animates
on random values still draws the same frame twice.

`MovieClipLoader` loads only engine images. An image slot is a named blank bitmap that the engine
adds to the movie before it starts, with a rectangle shape filled by it. `loadClip("img://name",
target)` places that shape in the target at depth 0, then sends `onLoadStart`, `onLoadComplete`, and
`onLoadInit` on the next tick. The engine paints the slot's texture later, so the picture can change
without a reload. Any other URL, or a slot that does not exist, reports `onLoadError` on the next
tick. Flash reports later too, and a component that calls `loadClip` from its constructor must not
be re-entered. CLIK's icon loader then gives up cleanly.

## Left out on purpose

- A Swift copy of the CLIK and `gfx` library. None is needed: `EventDispatcher`, `FocusHandler`,
  `NavigationCode`, `InputDelegate`, and the controls ship inside the movies as bytecode the
  interpreter runs.
- Shape-level hit testing. Both `MovieClip.hitTest` and pointer routing use bounding boxes.
- Text input. No key event edits a field.
- `createTextField`. A field made at runtime has no character to lay out, so it would hold text and
  draw nothing.
- Opcodes no vanilla movie uses: `ActionWith`, `ActionTry`, `ActionThrow`, `ActionSetTarget`,
  `ActionSetTarget2`, `ActionGetURL`, `ActionGetURL2`, `ActionWaitForFrame`, `ActionWaitForFrame2`,
  and `ActionEnumerate` (only `ActionEnumerate2` occurs). They parse and run as counted no-ops.
- `Key.isToggled` answers false. OpenSky injects keys and owns no keyboard, so a toggle state would
  be invented.

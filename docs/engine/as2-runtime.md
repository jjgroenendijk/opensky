---
type: Subsystem
title: AS2 runtime
description: The ActionScript 2 bytecode interpreter - value model and ECMAScript
  coercions, the object and function model, bounded execution, the display list it
  drives, event dispatch and input routing, the GameDelegate bridge, and the tally
  of everything not implemented.
tags: [engine, swf, actionscript, ui, scaleform]
timestamp: 2026-07-26T00:00:00Z
---

# AS2 runtime

Todo 8.3.2. The virtual machine that executes the ActionScript 1/2 bytecode
[`SWFActionParser`](/formats/swf.md) frames, plus the display objects it drives.

The milestone landed in three phases. Phase 1 is the interpreter and its object model —
values, coercions, prototypes, functions, bounds, and the `AS2Host` seam. Phase 2 is the
runtime display list behind that seam: a mutable clip tree, timeline stepping, the
property surface, and the draw-command stream the [screen-space UI
layer](/rendering/ui.md) renders. Phase 3 is interaction: event dispatch, input routing
and hit testing, the timer wheel the CLIK component library needs, focus and keyboard
navigation, and the `gfx.io.GameDelegate` bridge with its invoke log. Phase 4 —
per-menu game-data APIs — stays deferred to the milestones that own the data; see the
[AS2 scope decision](/decisions/swf-as2-scope.md).

Vanilla Skyrim menus are class-registration code. The measured inventory (milestone 8.3.1,
`openskycli swf action-sweep`) found 1,127 `DoInitAction` blocks against 2,163 timeline
`DoAction` blocks, 455 `ActionExtends`, 456 `ActionInstanceOf`, 1,535 `addProperty` calls,
894 `ASSetPropFlags` calls, and 3,526 references to `_global`. So the interesting result of
running a vanilla movie's bytecode is not a frame — it is the set of constructors left in
`_global` and handed to `Object.registerClass`. Both are readable from `AS2Runtime`.

The interpreter lives in `opensky/Formats/SWF/AS2/` and the display runtime in
`opensky/Formats/SWF/Runtime/`. The prefixes mark the boundary: `SWF*` types parse bytes
off disk, `AS2*` types execute the bytecode those parsers framed, and the two never share
a type. The `Runtime/` files are the one deliberate meeting point — they are named `SWF*`
because they are made of decoded characters and timelines, and they are the only place that
holds both an `AS2Object` and a `SWFPlacement`. Both directories sit under `Formats/SWF/`
because they consume that format and have no rendering dependency: they do not import
AppKit and build into both the app and `openskycli`.

## One virtual machine per movie

Each movie gets its own `AS2Runtime` and therefore its own `_global`. The
[scope decision](/decisions/swf-as2-scope.md) left this open; it is closed here, and the
evidence is in the files. `inventorymenu.swf`, `startmenu.swf`, and `hudmenu.swf` each
carry byte-identical `DoInitAction` blocks — 8,490, 5,108, 3,621, 2,374, 2,974, 941, and
612 bytes among others — so every menu already embeds its own private copy of the CLIK
library rather than expecting a shared one. Sharing in vanilla happens at the
character-dictionary level through `ImportAssets2` (fonts, `sharedcomponents.swf`), not
through `_global`.

A shared machine would therefore gain nothing and cost isolation: one menu's
`ASSetPropFlags` or prototype patch would reach every other menu, and a mod movie could
overwrite a vanilla class globally. Per-movie also makes teardown trivial — dropping the
`SWFMovieRuntime` drops the whole object graph.

## Value model

`AS2Value` is the six ECMAScript types (ECMA-262 3rd edition, section 8): `undefined`,
`null`, `boolean`, `number` (a `Double`), `string`, and `object`. Objects are reference
types; everything else is carried by value. ActionScript adds no value type of its own —
`MovieClip` and friends are ordinary objects that report a different `typeof`.

`AS2Value`'s `Equatable` conformance *is* strict equality (`ActionStrictEquals`, ECMA-262
11.9.6): same case, same value, objects by identity, NaN unequal to itself, `-0` equal to
`0`.

`typeof` deviates from ECMAScript in two documented places: `typeof null` is `"null"`, not
`"object"`, and an object may override its answer through `AS2Object.typeOverride` so a
display object can report `"movieclip"`.

## Coercions

`AS2Coercion` implements the primitive conversions; `ToPrimitive` needs to call `valueOf`
and `toString` on an object, so it lives on the interpreter
(`AS2Interpreter.toPrimitive(_:hint:)`) and hands the result back down.

| Rule | Reference | Notes |
|---|---|---|
| `ToBoolean` | ECMA-262 9.2 | Empty string is false from SWF 7; earlier versions use "reads as a non-zero number" |
| `ToNumber` | ECMA-262 9.3, 9.3.1 | Plus the ActionScript `0x` hexadecimal form. `undefined` is NaN from SWF 7, `0` before |
| `ToString` | ECMA-262 9.8, 9.8.1 | `undefined` is `"undefined"` from SWF 7, `""` before |
| `ToInt32` / `ToUint32` | ECMA-262 9.5, 9.6 | Done in `Double` so non-finite and out-of-range inputs cannot trap |
| Abstract equality | ECMA-262 11.9.3 | `null == undefined`, but `null == 0` is false |
| Strict equality | ECMA-262 11.9.6 | `AS2Value.==` |
| Relational | ECMA-262 11.8.5 | Two strings compare by UTF-16 code unit; anything else is numeric, NaN yields false |
| `ActionAdd2` | ECMA-262 11.6.1 | Both operands become primitives first; a string on either side makes it a concatenation |

The two version-dependent rules are why `AS2Coercion` carries a `swfVersion` instead of
being a namespace of static functions. `AS2Coercion.latest` is SWF 9, which is what vanilla
Scaleform menus are published at.

Number formatting follows ECMA-262 9.8.1: an integral magnitude below 1e21 prints
positionally (`100000000000000000000`), everything else uses Swift's shortest round-trip
form with the exponent normalized to the ECMAScript spelling (`1e+21`, `1e-7`). That last
step is an approximation of the specification's digit-generation algorithm and is pinned by
`AS2CoercionTests.numberToStringMatchesECMAFormatting`.

## Object model

`AS2Object` is a class with an insertion-ordered property table, a `__proto__` link
(`prototype`), and per-property attributes.

- **Attributes** — `dontEnumerate`, `dontDelete`, `readOnly`, matching the bits
  `ASSetPropFlags` toggles. That function is an undocumented Flash built-in with no entry in
  any specification, so the bit values here are recorded as observed, not cited.
- **Accessors** — a slot may hold a getter/setter pair instead of a value.
  `Object.prototype.addProperty(name, getter, setter)` installs one. The object stores the
  pair; the interpreter invokes it, because calling needs an execution context. The
  `__get__name` / `__set__name` naming the ActionScript 2 compiler emits for class
  properties is also honored, as a fallback after the ordinary lookup fails.
- **Arrays** — an object is array-like when `arrayLength` is non-nil. Elements live in the
  ordinary property table under their decimal names, as ECMAScript specifies; `length` is
  synthesized on read and truncates on write.
- **Prototype walks** are bounded by `AS2Object.prototypeChainLimit` (64), so a `__proto__`
  cycle built by malformed bytecode cannot hang a lookup.
- **Host payload** — `hostPayload` is an opaque `AnyObject` the engine attaches. The
  interpreter never inspects it, but its presence is what routes an unresolved member to
  `AS2Host`. This is the attachment point for display objects.

Functions are objects with a `callable`, either a Swift closure (`AS2NativeBody`) or a
bytecode body (`AS2BytecodeBody`). A bytecode function does not own its bytes: the
`ActionDefineFunction` header names a `codeSize` and the body is the next `codeSize` bytes
of the same stream, so the closure keeps its block plus the byte offset the body starts at
and reads the records back through `SWFActionBlock.records(from:byteCount:)`. It also keeps
the scope chain, the constant pool, and the variable target it was defined under.

`ActionExtends` builds the bridge prototype Flash builds: a fresh object whose `__proto__`
is the superclass prototype, carrying `constructor` and `__constructor__` pointing at the
superclass, installed as the subclass's `prototype`. `super` is then a binding object whose
prototype is the superclass prototype and whose `superThis` re-binds `this` to the original
receiver, which makes both `super.method()` and a bare `super(...)` constructor call work
off the same object.

### `super` resolves from the running class, not from the receiver

A binding derived from `this.__proto__` is only correct one level deep. `this` does not
change as a constructor chain is walked, so the base constructor's `super` resolves to the
constructor it was just reached through and calls itself until the depth cap aborts it —
issue #136, and three levels is the vanilla shape, because a CLIK component extends
`gfx.core.UIComponent`, which extends `MovieClip`.

`AS2Frame.basePrototype` is what the binding is built from instead: the prototype of the
class whose method the frame is running. Each frame gets it from the call that started it
(`AS2CallSite.base`):

- **`new C()`** — the constructor's own `prototype` object.
- **`obj.method()`** — the prototype the method resolved on
  (`AS2Interpreter.memberHome(_:of:)`), or nil when the receiver owns the slot itself, in
  which case the receiver's prototype is the fallback.
- **A call through a `super` binding** — the superclass prototype the binding recorded in
  `AS2Object.superBase` when it was built, so the next `super` up the chain starts one level
  higher.

Only the class's *own* `__constructor__` names the superclass; the inherited one belongs to
the superclass and would name the wrong parent. The frame's base is assigned before
parameter binding, because `ActionDefineFunction2`'s `PreloadSuper` builds the `super`
register at that moment and vanilla constructors call `super()` through that register rather
than by name.

## Execution

`AS2Runtime` is the per-movie object an engine holds: `_global`, the built-in prototypes,
the class registrations, the limits, the tally, and the trace log. `AS2Interpreter` is
created per invocation and carries only its own budget and call depth.

Entry points:

```swift
func execute(_ block: SWFActionBlock, target: AS2Object? = nil) -> AS2ExecutionResult
func execute(_ initAction: SWFDoInitAction, target: AS2Object? = nil) -> AS2ExecutionResult
func invoke(_ function: AS2Value, thisValue: AS2Value, arguments: [AS2Value]) -> AS2ExecutionResult
func globalValue(_ name: String) -> AS2Value
func registeredClass(named symbol: String) -> AS2Object?
var registeredClassNames: [String] { get }
```

The loop walks `SWFActionBlock.records` by index; a branch converts its byte target back to
an index through `SWFActionBlock.index(atOffset:)`. A function body is an index range inside
the same block, so a `return` and a branch behave identically at any nesting depth. A branch
that lands in the middle of a record, or outside the body being executed, is a fault rather
than a silent reinterpretation of operand bytes as opcodes.

### The call stack

Calls run on the interpreter's own frame stack, not on the Swift stack. Each `AS2Frame`
carries its own record range and instruction pointer, so calling a bytecode function pushes
a frame and returns to the same loop; when that frame is popped, its `AS2FrameCompletion`
says where the value goes — onto the calling frame's operand stack for an ordinary call, or
through the `new` rule (the constructor's own object if it returned one, otherwise the fresh
instance) for a construction.

That is a change from the milestone 8.3.2 implementation, which called by recursing on the
Swift stack (issue #132). Recursion made `callDepth` a stack-safety limit that had to stay
at 64, and vanilla CLIK constructor chains nest deeper than that: every aborted constructor
was a component that never reached `EventDispatcher.initialize(this)`, which is why
`dispatchEvent`, `addEventListener`, and `textField` headed the missing-API tally. Raising
the cap was measured twice and crashed the test host both times — at 256 and again at 128.
With an explicit stack the depth a chain may reach is bounded by memory, so `callDepth` is a
policy limit and now matches Flash's own default of 256.

Swift recursion survives in exactly one place: a call that has to produce its value inside a
Swift call rather than back in the loop. That is a built-in re-entering bytecode
(`Function.prototype.call` and `.apply`) and a property accessor answering a member read or
write. `AS2Interpreter.call` is that path, and `reentryDepth` — a much smaller cap, raising
`reentryDepthExceeded` — is what keeps it from overflowing the Swift stack. Every other
call goes through `startCall`, which pushes a frame and never recurses.

Variable resolution is innermost-first through the scope chain, then `this`, then `_global`.
An assignment to a name nothing declared lands on the timeline target, not in the innermost
activation — that is ActionScript, not ECMAScript.

A name carrying separators is resolved twice over. The dotted spelling walks members from
its head component, so `gfx.controls.Button` reaches `_global.gfx.controls.Button`; only
when that misses does it fall through to the display-tree path resolver, which owns the
slash spelling and `..`. The order was measured rather than assumed: resolving the display
path first made every fully-qualified class reference in the vanilla CLIK library miss,
which is what put `Map.MapMarker` (67 hits), `Components.CrossPlatformButtons` (43), and
`gfx.controls.Button` (42) at the head of the phase-2 missing-API tally. Fixing the order
removed all three entirely.

`ActionDefineFunction2` fills preload registers from register 1 upward in the specification's
flag order: `this`, `arguments`, `super`, `_root`, `_parent`, `_global`. `suppressThis` and
`suppressSuper` are deliberately ignored, because `this` and `super` are answered from the
frame rather than from an activation slot.

## Bounds

Every invocation runs under `AS2Limits`. Bytecode arrives from a user's own game files and
nothing upstream validates it, so each way a stream can be wrong ends in a recorded
`AS2Fault` that aborts that invocation and nothing else.

| Limit | Default | Why |
|---|---|---|
| `actionBudget` | 1,000,000 | Shared by every nested call of one invocation. The largest vanilla action block is 5,886 records, so this leaves about two orders of magnitude of loop headroom while capping a runaway well under a second |
| `callDepth` | 256 | Calls run on the interpreter's own frame stack, so this is a policy limit and matches Flash's own 256-frame default rather than being sized for Swift stack safety |
| `reentryDepth` | 32 | Nested Swift re-entries into the interpreter — a built-in or a property accessor that needs a bytecode result synchronously. The only path that still costs Swift stack |
| `stackDepth` | 4,096 | Flash compiles expressions, not unbounded stack machines |
| `registerCount` | 256 | The `ActionDefineFunction2` header field is a `UInt8`; the deepest vanilla function uses 23 |
| `tallyNames` | 256 | Distinct names kept per tally table; totals keep counting past it |
| `faultRecords` | 64 | Faults kept verbatim; the count keeps rising |
| `traceEntries` | 512 | `ActionTrace` messages kept, oldest dropped first |
| `traceLength` | 512 | Characters kept per trace message |

Faults: `stackOverflow`, `invalidJump`, `truncatedBody`, `budgetExhausted`,
`callDepthExceeded`, `reentryDepthExceeded`. Each carries the byte offset it was raised at
and a stable `kind` string for reporting. `AS2ExecutionResult` reports the value, the
actions executed, and the fault if any. A faulted block leaves the runtime fully usable.

An empty-stack read is deliberately *not* a fault. Flash yields `undefined` and continues,
and vanilla bytecode depends on that: the compiler emits a join-point `ActionPop` that both
sides of a branch reach with an empty stack, which occurs in 666 of the 1,180 vanilla action
blocks. Treating it as malformed input would abort more than half of them. It is counted
instead, in `AS2Tally.stackUnderflows`.

## Host seam

`AS2Host` is the protocol the display layer will implement. Everything the interpreter
cannot answer from its own object model leaves through it:

```swift
func perform(_ command: AS2TimelineCommand, target: AS2Object)
func property(_ property: AS2DisplayProperty, of target: AS2Value) -> AS2Value?
func setProperty(_ property: AS2DisplayProperty, of target: AS2Value, to value: AS2Value) -> Bool
func targetPath(of object: AS2Object) -> String?
func object(atPath path: String, from origin: AS2Object) -> AS2Object?
func specialObject(_ kind: AS2SpecialTarget, relativeTo origin: AS2Object) -> AS2Object?
func member(_ name: String, of object: AS2Object) -> AS2Value?
func setMember(_ name: String, of object: AS2Object, to value: AS2Value) -> Bool
```

`AS2TimelineCommand` covers `ActionStop`, `ActionPlay`, `ActionGotoFrame`, and
`ActionGoToLabel`. `AS2DisplayProperty` is the numbered property table `ActionGetProperty`
and `ActionSetProperty` address; the specification defines the opcodes and that they take an
index, but not the table, so the index-to-name mapping is recorded here as observed from the
ActionScript property list. `AS2SpecialTarget` covers `_root`, `_parent`, and `_level0`.

Declining is normal — every method may return nil or false — and the interpreter turns a
decline into a tally entry, never an error. Member lookups only consult the host for objects
that carry a `hostPayload`, so the seam is not on the path of ordinary property misses.

`SWFRuntimeHost` is the real implementation and answers all of it from the display tree; its
back-reference to `SWFMovieRuntime` is weak, because `AS2Runtime` owns its host and the
runtime owns the `AS2Runtime`. `AS2RecordingHost` remains as the phase-1 stand-in: it
appends every request to a bounded `AS2HostEvent` list and declines all of them, which is
what the interpreter's own tests run against and what measures a movie's demands without a
display list.

## Display objects

`SWFDisplayObject` is one placed character: its depth, instance name, matrix, color
transform, clip depth, visibility, and — for a clip — its own `SWFTimeline`, playhead, and
play state. Children are keyed by depth and read back depth-ascending, which is the paint
order. A leaf is a shape, a static text, or an edit text.

Every node carries an `AS2Object` face so ActionScript can address it. The pair points both
ways: the node owns the object, and `AS2Object.hostPayload` holds a `SWFDisplayHandle`
whose reference back to the node is **weak**. A strong pair would never be freed, and the
weak side also gives the right semantics — script that kept a reference to a removed clip
sees its members go `undefined` rather than resurrecting it. Clips set
`typeOverride = "movieclip"` so `typeof` answers the way Flash does.

A named instance is also defined as a property of its parent's `AS2Object`. That is what
makes a bare `panel` resolve from a frame action and `_root.panel._x` resolve through the
ordinary member path; the host's own child lookup is the fallback for anything that missed.

Bounds are computed on demand (`SWFBoundsBox`): a leaf's character bounds, a clip's union
of its children's transformed bounds. `_width` and `_height` are the axis-aligned extent of
the *transformed* box, so a rotated clip is wider than its artwork, which is what Flash
reports.

## Bring-up and timeline execution

The runtime's whole public surface:

```swift
init(movieScene: SWFMovieScene, limits: AS2Limits = .standard)
func start()                                   // bring-up, idempotent
func advance()                                 // one explicit tick
func makeScene() -> SWFScene                   // regenerate the command stream
func sceneIfChanged() -> SWFScene?             // nil when nothing moved
@discardableResult
func invoke(_ name: String, on target: SWFDisplayObject? = nil,
            arguments: [AS2Value] = []) -> AS2ExecutionResult
var root: SWFDisplayObject { get }              // _root / _level0
var tally: AS2Tally { get };  var traceLog: AS2TraceLog { get }
```

`start()` runs the sequence the 8.3.1 measurement implies — vanilla menus are class
libraries, not timeline scripts:

1. every `DoInitAction` block, in tag order, against the root clip;
2. the root's frame 1 control tags, which instantiate characters as they are placed;
3. the root's frame-1 `DoAction` blocks.

Instantiating a placed sprite is where a movie comes alive. If the character id has a
linkage name (`ExportAssets`) and a class was registered against that name
(`Object.registerClass`), the constructor runs with the display object as `this` and the
class prototype becomes the node's `__proto__`. The clip's own frame 1 is applied *before*
the constructor, so a CLIK component's constructor sees the children it expects. Because a
registered class may not `extend MovieClip`, the built-in clip methods are also reachable
through the host as a fallback after the prototype chain misses — Flash resolves those
natively rather than through the chain.

`advance()` is the only thing that moves a playhead, and it moves every playing clip by one
frame, then dispatches `enterFrame` and fires the timers that came due. Stepping forward by
one applies just that frame's control tags, which is what a player does.

Any other jump *accumulates* the destination state from frame 1 — a display list is the sum
of every step before it and the tags carry no undo — and then reconciles the live children
against it (`SWFRuntimeGoto.swift`). Reconciling rather than rebuilding is the correction
phase 3 made to phase 2's shortcut, and it matters as soon as ActionScript is running: an
instance the destination frame still places at the same depth with the same character is
kept and re-applied, so a clip can attach a handler to a child, jump its own timeline, and
still find the handler there. `tweenmenu.swf` does exactly that — it wires `onRollOver` and
`onMouseDown` onto its four input rectangles in `InitExtensions`, then opens itself with a
`gotoAndPlay` two frames further on — and a rebuild-from-scratch left the menu unclickable.
Instances the destination does not place are unloaded; depths it introduces are
instantiated and brought up.

The destination frame's `DoAction` blocks run either way; skipped frames' do not, matching
`gotoAndStop`. A frame action that jumps its own clip re-enters this path, so re-entry is
capped at `maximumGotoDepth` (8) and the dropped blocks are counted in
`droppedFrameActions`.

`gotoAndStop`/`gotoAndPlay` accept a **one-based** frame number or a label, while
`ActionGotoFrame`'s operand is zero-based as the specification defines it. An unknown label
is a tally entry and leaves the playhead alone.

## Property surface

ActionScript property units are pixels and degrees; the display list is twips and matrix
terms. Every conversion goes through one constant (`twipsPerPixel`, 20), because getting it
wrong misplaces a whole menu without erroring — `SWFRuntimePropertyTests` pins each one.

| property | read | write |
|---|---|---|
| `_x`, `_y` | translation / 20 | rounded and clamped into the `Int32` twip domain |
| `_xscale`, `_yscale` | length of the matrix basis vector x 100 | rescales that basis vector |
| `_width`, `_height` | transformed bounding box / 20 | rescales so the box matches |
| `_rotation` | `atan2(RotateSkew0, ScaleX)` in degrees | rebuilds the linear part, keeping both basis lengths |
| `_alpha` | CXFORM alpha multiplier x 100 | sets that multiplier |
| `_visible` | node flag | node flag; a hidden node's whole subtree leaves the scene |
| `_name`, `_target` | instance name, slash path | `_name` writes and rebinds the parent's property |
| `_currentframe`, `_totalframes`, `_framesloaded` | one-based playhead, declared frame count | declined |
| `_xmouse`, `_ymouse` | injected pointer, mapped into the node's own space, in pixels | declined |
| `_droptarget`, `_url`, `_highquality`, `_focusrect`, `_soundbuftime`, `_quality` | fixed answers | declined |

The last row is answered rather than declined so a runtime with no window and no sound does
not crowd the missing-API tally with names that will never be implemented.

CLIK's `__width` / `__height` pair are **ordinary** properties, not display properties. The
host declines them, which is what lets the write fall through to the object's own table.

## Events

Three mechanisms deliver an event to a running movie, and the 8.3.1 clip-event measurement
decides how much weight each carries. Across all 53 vanilla movies only `construct` occurs
meaningfully (122 handlers in 24 movies); `load` and `enterFrame` occur once each, and
**every** mouse and key `CLIPACTIONS` event is zero.

- **Handler members** — `clip.onPress`, `clip.onRollOver`, `clip.onEnterFrame`. This is what
  vanilla actually uses: `gfx.controls.Button` assigns `onPress = handleMousePress` in
  `configUI`, and `tweenmenu.swf` assigns `onRollOver` and `onMouseDown` onto its input
  rectangles. `SWFMovieRuntime.dispatch(_:to:arguments:)` looks the name up through the
  ordinary prototype chain, so a handler inherited from a registered class behaves like one
  assigned on the instance. A node with no such handler is the normal case, not a fault.
- **`CLIPACTIONS` handlers** — parsed since milestone 8.3.1 and dispatched since phase 3.
  `SWFDisplayObject.clipActions` carries the placement's block;
  `dispatchClipEvent(_:to:keyCode:)` runs every record whose flags include the event and,
  for a `keyPress` record, only when the trapped key matches. Because vanilla registers no
  key clip handler at all, key dispatch counts registrations (`keyClipHandlers`) and skips
  the tree walk entirely when the count is zero.
- **Broadcaster listeners** — the `addListener` / `removeListener` convention `Key`,
  `Mouse`, `Stage`, and `Selection` share. `broadcast(_:from:arguments:)` calls the named
  message on every recorded listener and answers how many had one.

Lifecycle order for a newly placed instance follows the specification's `ClipEventFlags`
table, which states that `initialize` and `construct` fire when the clip is created, before
`load`: the clip's own frame 1 is built, `initialize` fires, the registered class
constructor runs, then `construct` and `load`. Removal fires `unload` while the child is
still attached, so `_root` and `_parent` still resolve inside the handler. `enterFrame`
fires once per `advance()` for every clip, root excluded.

## Input

Input is **injected**, never read. There is no clock, no `NSEvent`, and no global anywhere
on this path, so a test, the offscreen render path, and the app drive the same code and
produce the same frame.

```swift
nonisolated enum SWFInputEvent: Equatable {
    case pointerMoved(x: Double, y: Double)
    case pointerPressed(x: Double, y: Double)
    case pointerReleased(x: Double, y: Double)
    case pointerWheel(delta: Double)
    case keyDown(code: Int, ascii: Int)
    case keyUp(code: Int)
}

@discardableResult func handle(_ event: SWFInputEvent) -> Bool
```

Pointer coordinates are **movie stage pixels**, the space `Stage.width`, `Stage.height`, and
`_xmouse` are expressed in. `SWFInputMapping.stagePoint(viewportPoint:frameSize:viewportPixels:)`
converts a framebuffer pixel into that space by inverting the letterbox transform
`SWFViewportMapping.twipsToPixels` builds, and returns nil for a point in the letterbox
bars, which belongs to no part of the movie. Internally everything is twips, because the
display list is; one constant (`twipsPerPixel`) does every conversion.

`handle` answers whether the movie consumed the event, which is what lets the engine give an
unconsumed key to the world instead. A false answer is normal and never a fault.

Pointer routing:

- A move retargets the hover object and sends `rollOut` to the one it left and `rollOver` to
  the one it entered — or `dragOut` / `dragOver` when the button is held over the pressed
  object, which is what Flash does.
- A press sends `press` to the object under the pointer and records it; a release sends
  `release` when the pointer is still over that object and `releaseOutside` when it is not,
  which is how a CLIK button cancels cleanly.
- `onMouseMove`, `onMouseDown`, and `onMouseUp` are **global** in Flash: every clip that
  defines one is called wherever the pointer is, unlike `onPress`. Vanilla depends on the
  distinction — `tweenmenu.swf` wires each input rectangle with an `onRollOver` for
  highlighting and an `onMouseDown` for activation, and the second would never fire on a
  hit-target-only route. The runtime indexes clips with one of these member handlers or a
  matching `CLIPACTIONS` handler as properties and prototypes mutate. Pointer events walk
  that weak index in display-tree order instead of scanning every clip; detached clips are
  discarded. The `Mouse` broadcaster receives the same three messages.

Key routing:

- The `Key` broadcaster receives `onKeyDown` / `onKeyUp` first, because that is where CLIK's
  `gfx.managers.InputDelegate` registers itself. A listener is an **observer**, not a
  consumer: only `handleInput` answers whether it took the event, and vanilla movies
  register unrelated `Key` listeners (`Shared.GlobalFunc.IsKeyPressed` in `tweenmenu.swf`)
  that would otherwise swallow every keystroke. Delivery is unconditional; only the returned
  flag is an OR.
- Then the menu's own `handleInput` (below), then CLIK's `FocusHandler`, then the focused
  object's `onKeyDown` as a last resort.
- A key *release* is delivered to the broadcaster, the clip events, and the focused object,
  but **not** to `handleInput`. A vanilla menu's `handleInput` acts on the event rather than
  on its phase, so routing both edges of one keystroke moves a selection twice and lands
  back where it started. One press is one navigation event.

## Hit testing

`hitTest(stageTwips:)` walks the tree in reverse paint order and answers two things: the
topmost drawable node under the pointer, and the topmost *mouse-enabled* one, which is what
receives `onPress`. It respects `_visible` (an invisible subtree catches nothing), the
accumulated matrix chain (the point is carried down into each node's local space rather than
each box being carried up), and clip layers (a node masked by a `ClipDepth` layer is only hit
where the mask is, the same `(depth, clipDepth]` rule the scene generator uses).

A clip is mouse-enabled when it carries any of `onPress`, `onRelease`, `onReleaseOutside`,
`onRollOver`, `onRollOut`, `onDragOver`, `onDragOut`, `onMouseDown`, or `onMouseUp`, or a
mouse `CLIPACTIONS` handler. Flash routes a mouse event to a clip only when the clip can
handle one, and CLIK assigns exactly these in `configUI`.

**Resolution is bounding-box, not shape-level.** A node is hit when the point falls inside
its character bounds. That matches `MovieClip.hitTest`, which is bounding-box in Flash too,
and it matches what vanilla asks for — every mouse-enabled control in the CLIK library is a
rectangular button or list row. A rotated or non-rectangular control therefore has a
slightly generous hit area. Shape-level testing would need the tessellated outline and is
not implemented.

## Focus and navigation

Vanilla menus navigate through CLIK: `NavigationCode` is referenced 1,669 times across 34
movies and `FocusHandler` 420 times. The framework's own path is `InputDelegate` listening on
`Key`, translating a key code into a `gfx.ui.NavigationCode` string, wrapping it in a
`gfx.ui.InputDetails`, and dispatching an `input` event that `FocusHandler` routes down the
focus path to the focused component's `handleInput`.

A probe over `startmenu.swf` shows only half of that chain wakes up on its own:
`FocusHandler._instance` exists after bring-up while `InputDelegate._instance` does not, so
nothing has registered on `Key`. The engine therefore performs the step the absent
`InputDelegate` would have performed, and it does so with the movie's **own** constants
rather than strings invented here — `navigationEquivalent(forKey:)` reads
`gfx.ui.NavigationCode.UP` and friends off the movie, and `makeInputDetails(code:value:)`
constructs a real `gfx.ui.InputDetails` when the movie ships the class, falling back to a
plain object carrying the same five fields when it does not.

Two destinations, tried in order:

- `routeToMenuHandler(code:value:)` — the Bethesda menu-root convention. Every vanilla menu
  class defines `handleInput(details, pathToFocus)`: `TweenMenuObj`, `StartMenu`,
  `gfx.controls.Button`, `Shared.BSScrollingList`, and `FocusHandler` all carry the same
  two-argument shape. `menuInputHandler` finds the outermost clip that defines it,
  breadth-first from the root and capped at `maximumHandlerDepth` (3), which keeps the search
  on menu roots — a vanilla menu clip sits one or two levels below `_root`, while the CLIK
  controls that also define `handleInput` sit deeper and are reached by the menu's own
  forwarding.
- `routeToFocusHandler(code:value:)` — `gfx.managers.FocusHandler.instance.handleInput`, for a
  movie whose focus manager is live. The singleton is behind a getter, so reading it is a
  call, and calling it is also what creates it.

`Selection.setFocus` / `getFocus` round-trip through `focusTarget` as before; the focus path
handed to `handleInput` is the chain of clips between the handler and the focused object,
**filtered to clips that define `handleInput`**, empty when nothing has focus — which is what
a menu that owns its own selection state expects. The filter matters because a vanilla menu
nests its list under a plain holder clip (`startmenu.swf`: `Menu_mc` -> `MainListHolder` ->
`List_mc`), and the movie's own `handleInput` forwards down `pathToFocus[0]`; an unfiltered
path hands it the holder, which defines no `handleInput`, and the key is dropped (issue #229).

## Timers

`setInterval`, `clearInterval`, `setTimeout`, and `clearTimeout` are load-bearing, not a
convenience: they were the head of the missing-API tally once qualified class names started
resolving (1,204 `clearInterval` hits, 796 `setInterval`, 590 `invalidationIntervalID`
across the install). CLIK's `UIComponent.invalidate()` schedules its own `draw()` through
`setInterval(this, "_validate", 1)`, so a component that cannot set an interval never lays
itself out, never fills its text fields, and never becomes interactive.

A timer is measured in **ticks**, not wall-clock milliseconds. The millisecond argument is
converted with the movie's own header `FrameRate` (`timerTicks(milliseconds:)`, never zero,
capped at `maximumTimerTicks` = 3,600), and a timer fires from `advance()` — the same
explicit tick that moves a playhead. A timer scheduled by a callback during a firing pass
does not fire in that pass. Both ActionScript calling conventions are supported
(`setInterval(function, ms, …)` and `setInterval(object, "method", ms, …)`, the second being
the one CLIK uses), the method name is resolved at fire time so a movie can replace it
between fires, and the list is capped at `maximumTimers` (256) with the excess counted in
`dropped`.

## The `GameDelegate` bridge

`gfx.io.GameDelegate` is Scaleform's host channel and the one vanilla actually uses: 1,520
references across 38 of the 53 movies. OpenSky adopts its shape rather than inventing a
bridge, because the movies are unmodified and a different bridge would mean they call into
nothing.

The delegate itself is ActionScript that ships **inside** each movie — a probe over
`startmenu.swf` reads back `call`, `receiveResponse`, `addCallBack`, `removeCallBack`,
`receiveCall`, `initialize`, `responseHash`, `callBackHash`, and `nextID` on
`_global.gfx.io.GameDelegate` — so the engine does not reimplement it. It supplies the two
ends the delegate reaches for.

```swift
typealias SWFHostFunction = @Sendable (SWFHostCall) -> AS2Value?

func registerHostFunction(_ name: String, _ body: @escaping SWFHostFunction)
func removeHostFunction(_ name: String)
var hostFunctionNames: [String] { get }
@discardableResult func callHost(_ name: String, arguments: [AS2Value]) -> AS2Value?
@discardableResult func callMovie(_ name: String, arguments: [AS2Value] = []) -> AS2Value
@discardableResult func callMovie(
    _ name: String, atPath path: String, arguments: [AS2Value] = []
) -> AS2Value
var gameDelegate: AS2Object? { get }
var movieCallbackNames: [String] { get }
```

**Movie to engine.** `ExternalInterface.call` and `fscommand` are player built-ins and
therefore the engine's to provide; `GameDelegate.call` routes through the first. A registered
Swift handler answers, and an unregistered name is a logged no-op plus a tally entry — the
binding rule the [scope decision](/decisions/swf-as2-scope.md) fixed. `ExternalInterface` is
installed under both the bare global name and `flash.external.ExternalInterface`, because AS2
spells it either way.

Telling a response id from an ordinary argument cannot be done by shape, and guessing is a
real failure mode: `tweenmenu.swf` calls `HighlightMenu(3)` with the 3 as its only argument,
and a rule that treated any leading number as an id would silently drop it. The delegate's
own bookkeeping decides instead. It writes `responseHash[id]` immediately before the call
when the movie passed a callback and passes the literal -1 when it did not, so an id is a
number that is either -1 or a live `responseHash` key — and only a movie that ships a
delegate can produce either. A handler's value then travels back through
`GameDelegate.receiveResponse(id, value)`.

**Engine to movie.** `callMovie(_:arguments:)` invokes a callback the movie registered with
`addCallBack`, through `receiveCall`. A movie that ships no delegate falls back to a function
on the root clip, so the engine has one entry point either way; a name neither answers is a
tally entry and an unhandled log entry.

Some vanilla movies expose their host entry points on a named display-list instance instead
of registering a delegate callback. `hudmenu.swf` is one: a probe over the user's installed
movie found its HUD functions on `/HUDMovieBaseInstance`. The path overload resolves that
instance, invokes the function with the instance as `this`, and records the same handled or
unhandled engine-to-movie log entry. A missing path is a bounded missing-name tally entry and
an unhandled call, not a crash.

## Invoke log

Both directions land in `SWFInvokeLog`, which milestone 8.3.3 requires `Developer > UI Lab`
to expose.

```swift
nonisolated struct SWFInvokeEntry: Equatable {
    enum Direction: String { case movieToEngine = "movie->engine"
                             case engineToMovie = "engine->movie" }
    let direction: Direction;  let name: String
    let arguments: String;     let result: String
    let isHandled: Bool
}

nonisolated struct SWFInvokeLog: Equatable {
    let entryLimit: Int;  let textLimit: Int
    private(set) var entries: [SWFInvokeEntry]
    private(set) var total: Int
    private(set) var unhandled: Int
    var dropped: Int { get }
}
```

Bounded on both axes and counting past both: at most `entryLimit` (256) entries are kept,
oldest dropped first, while `total`, `unhandled`, and `dropped` keep counting; each argument
summary is clipped to `textLimit` (240) characters. An object is summarized by kind rather
than walked, because the log must not depend on an object graph that may be cyclic. The
runtime exposes `invokeLog` and `clearInvokeLog()`.

## Built-in display classes

`MovieClip`, `TextField`, `Stage`, and `Selection` were the head of the missing-API tally
after phase 1 — 168, 25, 7, and 179 hits respectively — so they are what phase 2
implements. They are Flash and Scaleform GFx built-ins with no specification behind them,
reimplemented from public ActionScript 2 API documentation and observed bytecode.

- **`MovieClip.prototype`** — `play`, `stop`, `gotoAndPlay`, `gotoAndStop`, `nextFrame`,
  `prevFrame`, `getDepth`, `getNextHighestDepth`, `getInstanceAtDepth`, `swapDepths`,
  `removeMovieClip`, `attachMovie`, `createEmptyMovieClip`, `hitTest`, `toString`.
  `hitTest` is bounding-box only; shape-level hit testing is not implemented.
- **`TextField.prototype`** — `SetText` and `SetTextHTML` (GFx extensions, 595 calls across
  31 vanilla movies), plus `setTextFormat`/`getTextFormat`, which are accepted and ignored
  because the layout path renders one font and color per field.
- **`Stage`** — a plain object, not a constructor: `width` and `height` in pixels from the
  movie's own `FrameSize` (OpenSky letterboxes rather than reflowing, so the stage never
  resizes), separate `visibleRect` and `safeRect` objects covering that full frame,
  `scaleMode`, `align`, `showMenu`, and a listener list. The two Scaleform GFx rectangles
  carry `x`, `y`, `width`, and `height`; OpenSky has no overscan crop or safe-area inset.
- **`Selection`** — `setFocus` and `getFocus` round-trip a focus target, and the range
  queries answer -1. Caret and range behavior still need a text-input implementation and are
  not there.

Phase 3 adds the rest of the player surface the component library needs: `Key` and `Mouse`
as real broadcasters (see [Input](#input)), the four timer globals (see [Timers](#timers)),
`ExternalInterface` and `fscommand` (see [the bridge](#the-gamedelegate-bridge)),
`getBounds` / `localToGlobal` / `globalToLocal` / `duplicateMovieClip` on
`MovieClip.prototype`, `flash.geom.Point` with `add` / `subtract` / `clone` / `equals`, the
deprecated global `random(n)`, and `MovieClipLoader`.

`MovieClipLoader` is the one deliberate stub. It implements the object and the listener
protocol but never loads anything: there is no second movie to load, and reaching outside
the movie is out of scope (`ActionGetURL` never appears in vanilla either). A `loadClip`
reports failure through `onLoadError` on the next tick — queued rather than sent inline,
because Flash delivers it asynchronously and a component that calls `loadClip` from its own
constructor must not be re-entered mid-construction — which lets CLIK's icon loader give up
cleanly instead of waiting forever. `Key.isToggled` answers false for the same class of
reason: OpenSky injects key events, it does not own a keyboard, so a toggle state would be
invented.

## Text

A field's runtime string is, in order: an explicit assignment (`field.text = "..."` or
`SetText`), the value of its `VariableName` binding, then the character's `InitialText`.
`SWFEditText.variableName` was decoded in milestone 8.2 and unread until now; writing the
field writes the bound variable back, so a movie that reads `_root.someVar` afterwards sees
the same string.

The string travels to the renderer on `SWFSceneItem.textOverride`, an additive field that
is nil on the static path, and `SWFTextLayout.editText(_:font:content:)` re-lays out that
run without fabricating a second `SWFEditText`.

## Scene generation

`SWFMovieRuntime.makeScene()` produces the same `SWFScene` / `SWFSceneCommand` /
`SWFSceneItem` vocabulary as the static `SWFScene.build(movie:)`, with the same clip
semantics and paint order, so the renderer consumes one stream type and never learns
whether ActionScript is running. `sceneIfChanged()` returns nil when nothing moved, which
is what makes an idle movie free.

Bounds on the tree: `maximumNodes` (4,096) caps instantiation — a runaway `attachMovie`
loop is counted in `droppedInstantiations` instead of exhausting memory — and
`maximumTreeDepth` (32) bounds every recursive walk.

## Tally and trace

The milestone's stated risk-management mechanism is that an unimplemented opcode or an
unknown host API becomes a logged no-op plus a tally entry rather than an error, so
`AS2Tally` is a first-class result:

- `unimplementedOpcodes` / `unimplementedTotal`, ranked by count through
  `rankedUnimplemented` with Adobe opcode names.
- `missingNames` / `missingTotal` / `unnamedMissing`, ranked through `rankedMissing`. This is
  where the CLIK/`gfx` framework and the per-menu data APIs land today.
- `faults` / `faultTotal`.
- `stackUnderflows` — empty-stack reads, which are normal rather than wrong (see above), so
  they do not count against `isClean`.
- `actionsExecuted`, `blocksExecuted`, `callsPerformed`, and `isClean`.

Both name tables cap at `tallyNames` distinct entries while the totals keep counting, so a
truncated table still reports how much it stopped naming. `AS2TraceLog` holds `ActionTrace`
output, clipped per message and bounded in count with a `dropped` count — nothing reaches
`print`.

## Built-ins

Only what class-registration code needs: `Object` (with `registerClass`, `addProperty`,
`hasOwnProperty`, `isPropertyEnumerable`, `isPrototypeOf`, `toString`, `valueOf`),
`Function` (with `call` and `apply`), `Array`, `String`, `Number`, `Boolean`, `Math`,
`ASSetPropFlags`, `isNaN`, `parseInt`, `parseFloat`, `NaN`, `Infinity`, and `_global`
itself. These are Flash built-ins rather than SWF structures, reimplemented from public
ActionScript 2 behavior and from ECMA-262 3rd edition section 15, which ActionScript follows
for all of them.

`Math.random` draws from a seeded xorshift64\* generator owned by the runtime rather than
the system generator, so a menu that animates on random values still renders the same frame
twice — the [rendering layer's determinism contract](/rendering/ui.md).

## Deliberately absent

- **A Swift reimplementation of the CLIK / `gfx` component library**: none is needed and
  none exists. `EventDispatcher`, `FocusHandler`, `NavigationCode`, `InputDelegate`,
  `Constraints`, and the button and list controls all ship inside the movies as AS2 the
  interpreter already executes; phase 3 supplies the player primitives they stand on and
  reads their constants back off the movie rather than inventing them. What is still
  missing is measured, not guessed: `dispatchEvent` (326 hits across the install),
  `addEventListener` (317), `invalidationIntervalID` (326), `textField` (265),
  `CLIK_loadCallback` (144), and `focusIndicator` (123) are reads that miss on components
  whose construction aborted — see the call-depth limit below.
- **Per-menu data APIs**: `InventoryDefines`, `_CategoriesList`, `EntriesA`, and the rest
  are phase 4, deferred to the milestones that own the data.
- **Shape-level hit testing**: bounding-box only, in both `hitTest(stageTwips:)` and
  `MovieClip.hitTest`.
- **Text input**: `Selection`'s caret and range queries answer -1, and no key event edits a
  field.
- **Opcodes no vanilla movie uses**: `ActionWith` (no `with` scope chain),
  `ActionTry`/`ActionThrow` (no exceptions), `ActionSetTarget`/`ActionSetTarget2`,
  `ActionGetURL`/`ActionGetURL2` (no external loading),
  `ActionWaitForFrame`/`ActionWaitForFrame2`, and `ActionEnumerate` (only `ActionEnumerate2`
  occurs). They frame correctly in the parser and execute as a tallied no-op.
- **The app surface**: the `Developer > UI Lab` controls that start, tick, drive, and
  inspect a runtime are the app-facing half of milestone 8.3 and land separately, over the
  `SWFMovieRuntime` and `Renderer` API described here.

## Verification

Device-free, synthetic fixtures only — no test reads a real `.swf`. Action bytes come from
`openskyTests/SWFActionFixture.swift`, the single byte emitter milestone 8.3.1 added;
`openskyTests/AS2Fixture.swift` adds record-size arithmetic so branch offsets and function
`codeSize` fields are computed rather than counted by hand.

- `AS2CoercionTests` — every conversion and comparison rule above, including
  `undefined`/`null` comparisons, NaN, `-0`, `"" == 0`, numeric strings, the SWF 6 string
  rules, and the 32-bit wrap.
- `AS2InterpreterTests` — every arithmetic, comparison, bitwise, stack, and register opcode;
  operand order; shift masking; constant-pool resolution including `constant16` and a stale
  index; forward jumps, a backward loop that terminates, a branch into the middle of a
  record, and a branch to the end of the block.
- `AS2FunctionTests` — register and named parameter binding, the preload flags, anonymous
  function literals, nested calls, captured constant pools, a body longer than its stream,
  the call-depth cap, two hundred nested calls completing on the interpreter's own frame
  stack, and a re-entrant `Function.prototype.call` chain stopping at the re-entry cap.
- `AS2ObjectModelTests` — object and array literals, `ActionEnumerate2` order, `ActionExtends`
  with `ActionInstanceOf` and `ActionCastOp`, prototype methods through `new` and
  `ActionCallMethod`, `super` reaching the base constructor with the derived instance,
  `addProperty` getters, `ASSetPropFlags`, and `Object.registerClass`.
- `AS2SuperChainTests` — the three-level hierarchy from issue #136: `super()` walking one
  level per call from `Leaf` through `Mid` to `Base`, two-level construction still reaching
  the base constructor, and `super.method()` resolving from the class that defined the
  method rather than from the receiver's prototype.
- `AS2LimitsTests` — budget exhaustion, empty-stack tallying, stack overflow, recovery after
  a fault,
  unimplemented-opcode tallying, missing-API tallying, the tally name cap, the trace log
  bounds, the timeline and display-property host routes, and a coverage check that all 58
  implemented opcodes are named Adobe actions.

Phase 2 adds three device-free suites over `openskyTests/SWFRuntimeFixture.swift`, which
assembles a movie whose sprite is exported under a linkage name and whose `DoInitAction`
registers a class against it:

- `SWFMovieRuntimeTests` — bring-up, a registered class running with the placed display
  object as `this`, a sprite with no linkage name, `start()` being idempotent, one-frame
  stepping and the wrap, a stopped clip staying put, `gotoAndStop` by number and by label
  through both the Swift API and `ActionGoToLabel`, backward jumps rebuilding the list, an
  unknown label being tallied, path resolution (`_root`, `_parent`, `..`, dotted, slash,
  instance names), target paths, member resolution, scene generation matching the static
  scene at frame 1, visibility removing a subtree, dirty tracking, and clip layers still
  producing begin/end pairs.
- `SWFRuntimePropertyTests` — every getter and setter above with its exact twip/pixel or
  degree conversion, a non-finite write clamping instead of trapping, rotation preserving
  scale, read-only properties refusing writes, `__width` not being a display property, and
  the three text paths (assignment, variable binding, write-back).
- `SWFRuntimeNativesTests` — the four globals resolving, the clip methods being present,
  `attachMovie` instantiating and constructing an exported character, an unknown linkage
  name being tallied, `createEmptyMovieClip`/`removeMovieClip`, depth queries and swaps,
  bounding-box `hitTest`, `Stage` size in pixels, `Selection` focus round-tripping, listener
  recording, and `SetText`/`SetTextHTML`.

Phase 3 adds three more device-free suites:

- `SWFRuntimeEventTests` — the CLIPACTIONS lifecycle order around the constructor
  (`initialize`, constructor, `construct`, `load`), `unload` on removal, `enterFrame` per
  tick and not during bring-up, a `keyPress` handler matching only its trapped key code,
  `Key` and `Mouse` being installed as broadcasters with the standard key constants,
  listeners receiving broadcasts until removed, `Key.getCode` / `Key.isDown` answering from
  injected state, intervals firing on ticks and stopping when cleared, timeouts firing once,
  the timer list's cap and drop count, and the millisecond-to-tick conversion.
- `SWFRuntimeInputTests` — hit testing finding the topmost mouse-enabled object, respecting
  the transform chain, ignoring an invisible object, and honoring a clip layer's mask;
  rollover and rollout on a move; press then release routing `onRelease`; press then leave
  then release routing `onDragOut` and `onReleaseOutside`; `onMouseDown` reaching a clip
  wherever the pointer is; `_xmouse` / `_ymouse` in the node's own space; an unconsumed key
  falling back to the focused object; navigation reaching the menu's `handleInput` on press
  and not on release; the focus path dropping holder clips that define no `handleInput`
  before it reaches the movie; `InputDetails` carrying the code and the movie's own navigation
  equivalent; and the viewport-to-stage mapping including the letterbox bars and a non-zero
  frame origin.
- `SWFGameDelegateTests` — a registered host function receiving the movie's call, an
  unregistered one tallying and logging unhandled, a response id routing the result back
  through `receiveResponse`, -1 consumed as an id with nothing sent back, a numeric argument
  that is *not* a response id being preserved, a registered callback invoked through
  `receiveCall`, a movie without a delegate falling back to a root function, a callback the
  movie never defined, and the invoke log's bound, drop count, clipping, and clear.

Pixel evidence is `RendererSWFDynamicAcceptanceTests` and
`RendererSWFInteractiveAcceptanceTests` — see the [rendering layer](/rendering/ui.md).

## Measured against the vanilla install

An env-gated probe (not committed — AGENTS.md "Legal & IP boundary") brought up all 53
vanilla `Interface/*.swf` movies through `SWFMovieRuntime`: every `DoInitAction` block, the
root's frame 1 with class instantiation, and the frame's `DoAction`.

Phase 3's sweep additionally ticks each movie once, so it executes `enterFrame` handlers and
timer callbacks that phase 2 never reached. The phase-3 column was re-measured after the
frame-stack rewrite (issue #132); the `super` column is the same sweep after `super`
resolution was fixed (issue #136) and is what the current engine produces.

| Measure | Phase 1 (interpreter) | Phase 2 (display runtime) | Phase 3 (interaction) | After `super` fix |
|---|---|---|---|---|
| Movies brought up | 53 | 53 | 53 | 53 |
| Movies with no fault and no unimplemented opcode | 53 | 37 | 26 | 53 |
| Faults | 0 | 49 | 394, all `callDepthExceeded` | 0 |
| Unimplemented opcodes reached | 0 | 0 | 0 | 0 |
| Classes registered | 108 | 108 | 305 | 305 |
| Display nodes instantiated | — | 4,805 | 4,889 | 4,889 |
| Draw commands generated | — | 1,633 | 1,658 | 1,658 |
| Distinct missing API names | 146 | 198 | 245 | 240 |
| Total missing-API hits | — | — | 2,527 | 3,754 |

Every vanilla movie now brings up and ticks without a single fault. The missing-API total
rose because the constructors that used to abort now run to their end and read the rest of
their own state: `dispatchEvent` (326 hits) and `addEventListener` (317) fell off the head
of the tally — `addEventListener` to 109 — and what replaced them is
`EventDispatcher`'s own mixin state and the component fields behind it (`_listeners` 585,
`invalidationIntervalID` 521, `textField` 271, `height` 246, `width` 240,
`CLIK_loadCallback` 227, `focusIndicator` 188, `inspectableGroupName` 186). Those are the
phase-4 data surface the [scope decision](/decisions/swf-as2-scope.md) defers, not aborted
work.

Every movement is a consequence of executing more, not of regressing. Qualified-name
resolution alone removed `Map.MapMarker` (67 hits), `gfx.controls.Button` (42),
`Components.CrossPlatformButtons` (43), and every other fully-qualified class reference from
the tally; the timer globals removed a further 2,000 hits (`clearInterval` 1,204,
`setInterval` 796); `flash.geom.Point`, `duplicateMovieClip`, and `random` removed roughly
1,900 more. Class registrations tripled (108 to 305) because constructors that previously
aborted now run to the `registerClass` call at their end.

Before the `super` fix the head of the phase-3 tally was one shape, and it was the same
shape as the faults: `dispatchEvent` (326), `invalidationIntervalID` (326),
`addEventListener` (317), `textField` (265), `CLIK_loadCallback` (144), `focusIndicator`
(123) — reads on components whose construction aborted before
`EventDispatcher.initialize(this)` copied the mixin onto them. The tail behind them is
per-menu data: `EntriesA` (54), `InventoryLists_mc` (20), `ListScrollbar` (20),
`_CategoriesList`, `InventoryDefines` — phase 4, exactly as the
[scope decision](/decisions/swf-as2-scope.md) phased it.

All 394 phase-3 faults were `callDepthExceeded`, concentrated in the largest movies
(`quest_journal.swf` 159, `racesex_menu.swf` 57, `startmenu.swf` 35, `modmanager.swf` 19,
`itemcard.swf` 17); 27 movies faulted and 26 did not. Each fault aborted one constructor and
left the movie usable, which is why 26 movies came up completely clean even then, and why
the interactive target below was one of them. All 53 do now.

### `super` resolution, not call depth, was the binding limitation

Phase 3 read the depth cap as the cause and issue #132 as the fix. The frame stack landed
(see [the call stack](#the-call-stack)) and the sweep was re-run at three caps in one
process: the phase-3 column above is what all three produced.

| Measure | `callDepth` 64 | 256 (shipping) | 4,096 |
|---|---|---|---|
| Faults, all `callDepthExceeded` | 394 | 394 | 394 |
| `reentryDepthExceeded` | 0 | 0 | 0 |
| Movies with no fault and no unimplemented opcode | 26 | 26 | 26 |
| Distinct missing API names | 245 | 245 | 245 |
| Total missing-API hits | 2,527 | 2,527 | 2,527 |
| Sweep wall-clock | 34.9 s | 36.4 s | 88.9 s |

The per-movie distribution is identical at all three caps too. Only the cost changes, and it
changes linearly with the cap, because a cycle that never terminates runs to whatever cap
exists before it aborts. No cap crashes the host any more — 4,096 completes cleanly, which
the recursive interpreter could not do at 128 — and no cap helps either.

The cycle was `super()`. `superBinding(for:)` derived the binding from the receiver — it
called `this.__proto__`'s `__constructor__` and re-bound `this` to the same instance — so
`this.__proto__` never advanced as the chain was walked, and the base constructor's `super`
resolved to the constructor it was just reached through. Two levels worked; three looped,
and three is the vanilla shape, because a CLIK component extends `gfx.core.UIComponent`,
which extends `MovieClip`. The top single fault site was the shared embedded CLIK library
(`quest_journal.swf` action block 172, byte-identical in `racesex_menu.swf` block 61 and
`startmenu.swf` block 76) at offset 1398, the empty-name `ActionCallMethod` that
`gfx.core.UIComponent`'s constructor uses to reach its base — a `super()` reaching the
binding through a `PreloadSuper` register rather than by name.

Resolving `super` against the class whose method is executing (see
[`super` resolves from the running class](#super-resolves-from-the-running-class-not-from-the-receiver))
retired all 394 faults: every one of the 53 movies now brings up and ticks clean, and
`quest_journal.swf` alone went from 159 faults to 0 — issue #136.

What #132 did change is the shape of the cost, not the tally: `racesex_menu.swf` fell from
180 faults to 57 on the frame stack alone (at the same cap of 64), the depth cap is a policy
number again, and `reentryDepthExceeded` is zero across the whole install — no vanilla menu
exercises the remaining Swift-recursive path at bring-up plus one tick.

### The interactive menu: `tweenmenu.swf`

The 8.3.3 gate asks for one vanilla menu that opens, navigates, and closes. The
[scope decision](/decisions/swf-as2-scope.md) nominated `startmenu.swf`; measurement rejected
it and chose `tweenmenu.swf` instead — Skyrim's four-way pause selector (Skills, Magic,
Inventory, Map).

`startmenu.swf` was measured and was gated on three things phase 3 did not own: 35
`callDepthExceeded` faults after bring-up, a `_root.CodeObj` host-object contract whose shape
was not readable from the bytecode, and the save-list data contract behind
`onFillCharacterListComplete`, `onSaveLoadBatchComplete`, and `ConfirmOKToLoad` — phase-4
work by definition. Two of the three have since been retired; see
[`startmenu.swf` re-measured](#startmenuswf-re-measured-at-851) below.
`tweenmenu.swf` had none of those: **0 faults**, 0 unimplemented opcodes,
39 display nodes, and its four options are structural clips in the movie rather than data
pushed by the engine. Its class `TweenMenuObj` carries exactly the surface the gate names —
`StartOpenMenuAnim`, `onFinishOpenMenuAnim`, `handleInput`, `onInputRectMouseOver`,
`onInputRectClick`, `StartCloseMenuAnim`, `onCloseComplete` — and milestone 8.5.1 still needs
`startmenu.swf`, so nothing is spent twice.

Measured end to end through `Renderer.sendSWFInput` and `Renderer.callSWFMovie` at 640x360,
with the movie's own frames as the state readout:

| Step | Driven by | UI-state delta | Changed pixels | Bridge |
|---|---|---|---|---|
| Static frame 1 | `setSWFMovie` | 20 draws | 24,490 over empty | — |
| Bring-up | `startSWFRuntime` | 39 nodes, 0 faults | 0 | — |
| **Open** | `SetPlatform`, `InitExtensions`, `StartOpenMenuAnim`, 20 ticks | menu frame 0 -> 10, playhead stops | 460 | `OpenAnimFinished()` movie -> engine |
| **Navigate** (keys) | `keyDown` left / up / right / down | selection frame 0 -> 2 -> 1 -> 3 -> 4 | 988 / 1,590 / 1,477 / 1,374 | `HighlightMenu(2)`, `(1)`, `(3)`, `(4)` |
| **Navigate** (pointer) | `pointerMoved` over each input rectangle | selection frame 1 -> 2 -> 3 -> 4 | 1,101 / 1,590 / 1,863 / 1,374 | `HighlightMenu(1)` … `(4)` |
| **Close** | `StartCloseMenuAnim`, 20 ticks | menu frame 10 -> 19, playhead stops | 24,691 | `CloseMenu()` movie -> engine |

Every input was consumed (`handle` returned true), the run ended with 0 faults and 0
unimplemented opcodes, and the invoke log held 12 entries with **0 unhandled** across both
directions. Twelve distinct names remain missing, all in the controller-focus path CLIK uses
for gamepads (`getControllerFocusGroup` 8, `findFocus` 4, `getControllerMaskByFocusGroup` 1)
plus the usual one-shot `_global` guard reads (`gfx`, `Shared`, `Components`). The menu's own
frame labels — `showMenu`, `hideMenu`, `startExpand`, `endExpand` — are decoded and
addressable.

### `startmenu.swf` re-measured at 8.5.1

Milestone 8.5.1 ([system menu](/engine/system-menu.md)) came back to the movie 8.3.3
rejected, and two of the three blockers were gone.

The **35 `callDepthExceeded` faults** were retired by the `super` resolution fix
(issue #136), along with the other 359. Bring-up plus five ticks now reports 0 faults and
0 unimplemented opcodes.

**`_root.CodeObj` is not a host object.** It was read as one because the bytecode only ever
calls through it. In fact the movie creates it itself — `StartMenu`'s constructor runs
`_root.CodeObj = this.codeObj = new Object()` and installs `_root.ReleaseCodeObject` and
`_root.onCodeObjectInit` beside it — so after plain bring-up the object is already present
and empty. All 16 names the bytecode reaches on it are outbound calls with no data reads,
and every one is the Bethesda.net login path: `initLogin`, `BeginLogin`, `GetBnetUpdate`,
`ModsBlockedByBnet`, `CClubBlockedByPermissions`, `CClubBlockedByBnet`, `startEditText`,
`endEditText`, `onLoginScreenOpen`, `onLoginScreenClose`, `attemptLogin`,
`createQuickAccount`, `AcceptLegalDoc`, `PopulateEULA`, `PlaySound`, `PlayOKSound`. Nothing
needs synthesizing; the engine attaches no-op natives and the login screen never opens.

**The save-list contract still stands**, and it is why the bridge answers
`sendMenuProperties` with "no saves": the list comes up without `$CONTINUE`, with `$LOAD`
disabled.

The list itself is entirely engine-driven, through three calls in order — `SetPlatform(0,
false)` and `InitExtensions` directly on `/MenuHolder/Menu_mc`, then the `GameDelegate`
callback `sendMenuProperties` with 14 flat arguments. `InitExtensions` is what registers
that callback: the movie goes from 4 registered callbacks to 17. `setupMainMenu` then
clears `MainList.EntriesA`, pushes one `{text, index, disabled, showIcon}` row per enabled
capability, and calls `InvalidateData()`.

| Stage | Faults | Unimplemented | Draw calls | Rows | Changed pixels |
|---|---|---|---|---|---|
| Bring-up + 5 ticks | 0 | 0 | 152 | none (authored placeholders) | 4,285 over empty |
| `activate` + 30 ticks | 0 | 0 | 89 | `$NEW`, `$LOAD`, `$CREDITS`, `$QUIT` | 5,522 over empty |

Answering the outbound side takes six names: `myLog`, `PlaySound`, `PlayOKSound`,
`StartState`, and `currentState` as `GameDelegate` host functions, plus `gfxProcessSound`
as a plain `_global` native. `myLog` alone accounts for 24 calls, and all of them happen
inside the movie's own `DoInitAction` blocks — which is why `Renderer.startSWFRuntime` grew
a `prepare` hook that runs before `start()`. With those six registered the invoke log ends
at **0 unhandled of 36**, and 44 distinct names remain missing, all CLIK cosmetics
(`_listeners` 50, `height`/`width` 40 each, `invalidationIntervalID` 40, `apply` 33,
`CLIK_loadCallback` 17).

Both measured failures are closed. `InitExtensions` installs the shared `MovieClip.Lock`
helper, whose `BR` branch positions `/MenuHolder` from `Stage.visibleRect` and
`Stage.safeRect`. OpenSky exposed neither Scaleform GFx rectangle, so the reads became
`undefined`, numeric coercion made every edge zero, and the helper moved the holder from
`(1280, 720)` to `(0, 0)`. Publishing separate full-frame rectangles keeps the holder at the
stage's lower-right corner and makes the last table row visible (issue #230). Arrow keys
through `handle()` were consumed without effect because `routeToMenuHandler` handed
`StartMenu.handleInput` the raw display chain `[MainListHolder, List_mc]` and the holder clip
defines no `handleInput`. Filtering the focus path to clips that define `handleInput` sends
`[List_mc]`, which drives selection and dispatches the row's outbound call (issue #229).

Finally, a scope finding worth recording: `startmenu.swf` is Skyrim's **title screen**. Its
1,674-string pool contains no `$SETTINGS`, and its rows are Continue/New/Load/Creations/
Mods/Credits/Quit/Help. The in-game system menu is `quest_journal.swf`, whose pool carries
`$SYSTEM`, `$SETTINGS`, `$CONTROLS`, `$SAVE`, `$LOAD`, `$QUIT`, and the whole settings
tree. Issue #231.

## Limits / next

- The probes above are not a committed surface. Turning them into an
  `openskycli swf action-run` sweep and a `Developer > UI Lab` readout is the app-facing
  half of this milestone.
- **`super` in a method the receiver owns.** When a function is an own property of the
  instance rather than of a class prototype, the frame has no class to walk up from and
  falls back to the receiver's prototype — the pre-#136 behavior, correct for one level.
  No vanilla movie has been observed to do this in a `super` chain.
- **Re-entry depth.** Bytecode calls no longer recurse on the Swift stack (issue #132), but a
  built-in or a property accessor that calls back into bytecode still does, under
  `reentryDepth` (32). No vanilla movie has been observed to reach it; a chain of accessors
  that each read another accessor would.
- `ActionCallFunction` binds `this` to the calling frame's `this`. Flash binds it to the
  target clip when the name did not resolve on an object; the two agree for timeline code and
  can differ inside a method.
- The scope chain has no `with` frame, because no vanilla movie emits `ActionWith`.
- Hit testing is bounding-box only, in both directions (`hitTest(stageTwips:)` and
  `MovieClip.hitTest`), and `setTextFormat` is accepted and ignored.
- `menuInputHandler` finds a menu root by searching for `handleInput` breadth-first to depth
  3. That is the observed vanilla shape, not a declared contract; a movie that buries its
  menu root deeper, or that puts a CLIK control that shallow, would need the engine to name
  the handler explicitly.
- `MovieClipLoader` never loads: a `loadClip` always reports `onLoadError`.
- `createTextField` is not implemented — a runtime-created field has no character
  definition to lay out, so it would hold text and draw nothing.

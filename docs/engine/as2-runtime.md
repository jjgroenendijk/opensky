---
type: Subsystem
title: AS2 runtime
description: The ActionScript 2 bytecode interpreter - value model and ECMAScript
  coercions, the object and function model, bounded execution, the host protocol the
  display layer plugs into, and the tally of everything not implemented.
tags: [engine, swf, actionscript, ui, scaleform]
timestamp: 2026-07-25T00:00:00Z
---

# AS2 runtime

Todo 8.3.2. The virtual machine that executes the ActionScript 1/2 bytecode
[`SWFActionParser`](/formats/swf.md) frames, plus the display objects it drives.

The milestone landed in two phases. Phase 1 is the interpreter and its object model —
values, coercions, prototypes, functions, bounds, and the `AS2Host` seam. Phase 2 is the
runtime display list behind that seam: a mutable clip tree, timeline stepping, the
property surface, and the draw-command stream the [screen-space UI
layer](/rendering/ui.md) renders. Input routing, event dispatch, the CLIK/`gfx` component
framework, and the `GameDelegate` bridge are phase 3 and are **not** here; see the
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

Variable resolution is innermost-first through the scope chain, then `this`, then `_global`.
An assignment to a name nothing declared lands on the timeline target, not in the innermost
activation — that is ActionScript, not ECMAScript.

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
| `callDepth` | 64 | The interpreter recurses on the Swift stack and a worker thread's stack is far smaller than the main thread's. Set for stack safety, not for parity with Flash's 256-frame default |
| `stackDepth` | 4,096 | Flash compiles expressions, not unbounded stack machines |
| `registerCount` | 256 | The `ActionDefineFunction2` header field is a `UInt8`; the deepest vanilla function uses 23 |
| `tallyNames` | 256 | Distinct names kept per tally table; totals keep counting past it |
| `faultRecords` | 64 | Faults kept verbatim; the count keeps rising |
| `traceEntries` | 512 | `ActionTrace` messages kept, oldest dropped first |
| `traceLength` | 512 | Characters kept per trace message |

Faults: `stackOverflow`, `invalidJump`, `truncatedBody`, `budgetExhausted`,
`callDepthExceeded`. Each carries the byte offset it was raised at and a stable `kind`
string for reporting. `AS2ExecutionResult` reports the value, the actions executed, and the
fault if any. A faulted block leaves the runtime fully usable.

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
frame. Stepping forward by one applies just that frame's control tags, which is what a
player does; any other jump rebuilds the clip's children from frame 1 to the destination,
because a display list is the accumulation of every step before it and the tags carry no
undo. The destination frame's `DoAction` blocks run either way; skipped frames' do not,
matching `gotoAndStop`. A frame action that jumps its own clip re-enters this path, so
re-entry is capped at `maximumGotoDepth` (8) and the dropped blocks are counted in
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
| `_droptarget`, `_url`, `_highquality`, `_focusrect`, `_soundbuftime`, `_quality`, `_xmouse`, `_ymouse` | fixed answers | declined |

The last row is answered rather than declined so a runtime with no window, no sound, and no
pointer does not crowd the missing-API tally with names that will never be implemented. The
pointer pair reads 0 until input arrives in phase 3.

CLIK's `__width` / `__height` pair are **ordinary** properties, not display properties. The
host declines them, which is what lets the write fall through to the object's own table.

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
  resizes), `scaleMode`, `align`, `showMenu`, and a listener list.
- **`Selection`** — `setFocus` and `getFocus` round-trip a focus target, and the range
  queries answer -1. Focus *behavior* is not implemented: nothing routes input to the
  focused object, draws an indicator, or dispatches `onSetFocus`. Recording it keeps the
  name off the tally and leaves state for the phase-3 focus manager to adopt.

`addListener`/`removeListener` record listeners on `Stage` and `Selection` without
dispatching to them, for the same reason.

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

- **The CLIK / `gfx` component framework**: `EventDispatcher`, `addEventListener`,
  `dispatchEvent`, `Constraints`, `FocusHandler`, `NavigationCode`, and the button and list
  controls. A reference to any of them resolves to `undefined` and lands in the tally as a
  named missing API — the coverage evidence phase 3 starts from.
- **Input and event dispatch**: nothing routes a mouse or key event anywhere, `Mouse` and
  `Key` do not exist, and `Selection` records focus without acting on it.
- **The `GameDelegate` bridge**: `gfx.io.GameDelegate` is 1,520 uses in 38 movies and is
  phase 3's engine-to-movie channel. `SWFMovieRuntime.invoke(_:on:arguments:)` is the seam
  it will be built on.
- **Per-menu data APIs**: `InventoryDefines`, `_CategoriesList`, `EntriesA`, and the rest
  are phase 4, deferred to the milestones that own the data.
- **Opcodes no vanilla movie uses**: `ActionWith` (no `with` scope chain),
  `ActionTry`/`ActionThrow` (no exceptions), `ActionSetTarget`/`ActionSetTarget2`,
  `ActionGetURL`/`ActionGetURL2` (no external loading),
  `ActionWaitForFrame`/`ActionWaitForFrame2`, and `ActionEnumerate` (only `ActionEnumerate2`
  occurs). They frame correctly in the parser and execute as a tallied no-op.
- **CLIPACTIONS event dispatch**: the handlers are parsed and reachable as action blocks, but
  nothing routes an event to them yet.
- **The app surface**: no `Developer > UI Lab` control starts, ticks, or inspects a runtime
  yet. That is the app-facing half of milestone 8.3 and lands alongside the invoke log and
  op tally the 8.3.3 gate asks for.

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
  and the call-depth cap.
- `AS2ObjectModelTests` — object and array literals, `ActionEnumerate2` order, `ActionExtends`
  with `ActionInstanceOf` and `ActionCastOp`, prototype methods through `new` and
  `ActionCallMethod`, `super` reaching the base constructor with the derived instance,
  `addProperty` getters, `ASSetPropFlags`, and `Object.registerClass`.
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

Pixel evidence is `RendererSWFDynamicAcceptanceTests` — see the
[rendering layer](/rendering/ui.md).

## Measured against the vanilla install

An env-gated probe (not committed — AGENTS.md "Legal & IP boundary") brought up all 53
vanilla `Interface/*.swf` movies through `SWFMovieRuntime`: every `DoInitAction` block, the
root's frame 1 with class instantiation, and the frame's `DoAction`.

| Measure | Phase 1 (interpreter only) | Phase 2 (display runtime) |
|---|---|---|
| Movies brought up | 53 | 53 |
| Movies with no fault and no unimplemented opcode | 53 | 37 |
| Faults | 0 | 49, all `callDepthExceeded` |
| Unimplemented opcodes reached | 0 | 0 |
| Classes registered | 108 | 108 |
| Display nodes instantiated | — | 4,805 |
| Draw commands generated | — | 1,633 |
| Distinct missing API names | 146 | 198 |

Both movements are expected. `Selection`, `MovieClip`, `TextField`, and `Stage` — 379 hits
between them — left the tally entirely, while running constructors reaches code phase 1
never executed, which surfaces names that were previously unreachable. The new head is the
framework and the per-menu data contracts, in order of frequency: `Map.MapMarker` (67),
`addEventListener` (49), `Components.CrossPlatformButtons` (43), `gfx.controls.Button`
(42), `Shared` (41), `gfx` (41), `Components` (30), `addListener` (28, now on `Key`,
`Mouse`, and `MovieClipLoader` rather than `Stage`/`Selection`), `InventoryLists_mc` (20),
and `MovieClipLoader` (20). That is phase 3 and phase 4 work, exactly as the
[scope decision](/decisions/swf-as2-scope.md) phased it.

The 49 faults are all one shape: deep CLIK constructor chains exceeding the 64-frame
`callDepth` cap, concentrated in the largest movies (`modmanager.swf` 19,
`racesex_menu.swf` 8, `quest_journal.swf` 6). Raising the cap is not the fix — a probe run
at 256 crashed the test host on a Swift stack overflow, which confirms the cap's stated
rationale. Making the interpreter iterative rather than recursive is the real fix and is
not phase 2 work. Each fault aborts one constructor and leaves the movie usable, which is
why 37 movies still come up completely clean.

## Limits / next

- The probe above is not a committed surface. Turning it into an
  `openskycli swf action-run` sweep and a `Developer > UI Lab` readout is the app-facing
  half of this milestone.
- **Call depth.** The interpreter recurses on the Swift stack, so `callDepth` is 64 and
  deep CLIK constructor chains hit it (see above). An iterative call implementation would
  remove the cap as a correctness limit.
- `ActionCallFunction` binds `this` to the calling frame's `this`. Flash binds it to the
  target clip when the name did not resolve on an object; the two agree for timeline code and
  can differ inside a method.
- The scope chain has no `with` frame, because no vanilla movie emits `ActionWith`.
- `hitTest` is bounding-box only, `_xmouse`/`_ymouse` read 0, and `setTextFormat` is
  accepted and ignored.
- A clip's `onEnterFrame` is not called: `advance()` steps playheads but dispatches no
  events, because event dispatch is phase 3.

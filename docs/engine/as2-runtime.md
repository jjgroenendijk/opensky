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
[`SWFActionParser`](/formats/swf.md) frames. It is the interpreter and its object model
only: there are no display objects, no timeline stepping, no input, and no rendering. Those
arrive in a later milestone and plug into the host protocol this milestone leaves behind.

Vanilla Skyrim menus are class-registration code. The measured inventory (milestone 8.3.1,
`openskycli swf action-sweep`) found 1,127 `DoInitAction` blocks against 2,163 timeline
`DoAction` blocks, 455 `ActionExtends`, 456 `ActionInstanceOf`, 1,535 `addProperty` calls,
894 `ASSetPropFlags` calls, and 3,526 references to `_global`. So the interesting result of
running a vanilla movie's bytecode is not a frame — it is the set of constructors left in
`_global` and handed to `Object.registerClass`. Both are readable from `AS2Runtime`.

Everything lives in `opensky/Formats/SWF/AS2/`. The `AS2` prefix marks the boundary:
`SWF*` types parse bytes off disk, `AS2*` types execute the bytecode those parsers framed,
and the two never share a type. The directory sits under `Formats/SWF/` because the runtime
is the consumer of that format's action tags and has no rendering dependency — it does not
import AppKit and builds into both the app and `openskycli`.

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

`AS2RecordingHost` is this milestone's implementation: it appends every request to a bounded
`AS2HostEvent` list and declines all of them, which makes a movie's demands on the display
layer measurable before the display layer exists.

## Tally and trace

The milestone's stated risk-management mechanism is that an unimplemented opcode or an
unknown host API becomes a logged no-op plus a tally entry rather than an error, so
`AS2Tally` is a first-class result:

- `unimplementedOpcodes` / `unimplementedTotal`, ranked by count through
  `rankedUnimplemented` with Adobe opcode names.
- `missingNames` / `missingTotal` / `unnamedMissing`, ranked through `rankedMissing`. This is
  where `MovieClip`, `Stage`, `Selection`, and the `gfx` framework land today.
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

- **Display objects**: `MovieClip`, `TextField`, `Stage`, `Selection`, `EventDispatcher`,
  and the `gfx` framework. A reference to any of them resolves to `undefined` and lands in
  the tally as a named missing API — the coverage evidence the next milestone starts from.
- **Timeline stepping and rendering**: the timeline opcodes are decoded and routed, never
  executed.
- **Opcodes no vanilla movie uses**: `ActionWith` (no `with` scope chain),
  `ActionTry`/`ActionThrow` (no exceptions), `ActionSetTarget`/`ActionSetTarget2`,
  `ActionGetURL`/`ActionGetURL2` (no external loading),
  `ActionWaitForFrame`/`ActionWaitForFrame2`, and `ActionEnumerate` (only `ActionEnumerate2`
  occurs). They frame correctly in the parser and execute as a tallied no-op.
- **CLIPACTIONS event dispatch**: the handlers are parsed and reachable as action blocks, but
  nothing routes an event to them yet.
- **The app surface**: no `Developer > UI Lab` control exposes runtime state in this
  milestone. It arrives with the display layer, which is what makes the state worth looking
  at.

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

## Measured against the vanilla install

An env-gated probe (not committed — AGENTS.md "Legal & IP boundary") ran every
`DoInitAction` and timeline `DoAction` block of the 53 vanilla `Interface/*.swf` movies
through `AS2Runtime`:

| Measure | Result |
|---|---|
| Movies decoded | 53 |
| Action blocks executed | 1,180 |
| Faults | 0 |
| Unimplemented opcodes reached | 0 |
| Classes left in `Object.registerClass` | 108 |
| Distinct missing API names | 146 |

The missing names are the display and framework surface, in order of frequency: `Selection`
(179), `MovieClip` (168), `Map.MapMarker` (67), `Components.CrossPlatformButtons` (43),
`gfx.controls.Button` (42), `gfx` (41), `Shared` (41), `addListener` (36), `TextField` (25),
`Stage` (7). Nothing in that list is an interpreter gap; all of it is the display layer the
next milestone builds behind `AS2Host`.

## Limits / next

- The probe above is not a committed surface. Turning it into a
  `openskycli swf action-run` sweep and a `Developer > UI Lab` readout belongs with the
  display layer, which is what makes the runtime state worth looking at.
- `ActionCallFunction` binds `this` to the calling frame's `this`. Flash binds it to the
  target clip when the name did not resolve on an object; the two agree for timeline code and
  can differ inside a method.
- The scope chain has no `with` frame, because no vanilla movie emits `ActionWith`.

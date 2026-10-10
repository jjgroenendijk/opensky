---
type: Subsystem
title: AS2 runtime
description: The ActionScript 2 bytecode interpreter - one machine per movie, the value model and
  ECMAScript coercions, the object and function model, super resolution, the frame stack, bounds,
  the tally, the built-ins, and what is left out on purpose.
tags: [engine, swf, actionscript, ui, scaleform]
---

# AS2 runtime

The AS2 runtime runs the ActionScript 1 and 2 bytecode that the [SWF action parser](/formats/swf-actions.md)
frames. Related pages:

- [AS2 display runtime](/engine/as2-display-runtime.md): the clip tree the bytecode drives, the
  property surface, and scene generation.
- [AS2 input and events](/engine/as2-input.md): events, input, hit testing, focus, and timers.
- [GameDelegate bridge](/engine/as2-game-delegate.md): calls between a movie and the engine, and
  what driving the vanilla menus showed.

Vanilla Skyrim menus are mostly class registration code. `openskycli swf action-sweep` counts 1,127
`DoInitAction` blocks against 2,163 timeline `DoAction` blocks, 455 `ActionExtends`, 456
`ActionInstanceOf`, 1,535 `addProperty` calls, 894 `ASSetPropFlags` calls, and 3,526 references to
`_global`. So the main result of running a vanilla movie's bytecode is not a frame. It is the set of
constructors left in `_global` and passed to `Object.registerClass`.

The interpreter is in `Sources/OpenSkyFormatsSWF/AS2/` and the display runtime in
`Sources/OpenSkyFormatsSWF/Runtime/`. `SWF*` types parse bytes. `AS2*` types run the
bytecode. The `Runtime/` files are the one meeting point: they hold both an `AS2Object` and a
placement. Both folders import no AppKit and build into the app and the CLI. What is in scope is on
the [AS2 scope decision](/decisions/swf-as2-scope.md) page.

## One machine per movie

Each movie gets its own runtime, and so its own `_global`. The files show why.
`inventorymenu.swf`, `startmenu.swf`, and `hudmenu.swf` each carry byte-identical `DoInitAction`
blocks (8,490, 5,108, 3,621, 2,374, 2,974, 941, and 612 bytes, among others). So every menu has its
own copy of the CLIK library. Vanilla shares at the character level, through `ImportAssets2` for
fonts and `sharedcomponents.swf`, not through `_global`.

A shared machine would gain nothing and lose isolation: one menu's `ASSetPropFlags` or prototype
patch would reach every other menu, and a mod movie could replace a vanilla class everywhere. One
machine per movie also makes teardown simple: dropping the movie drops its whole object graph.

## Values

A value is one of the six ECMAScript types (ECMA-262 3rd edition, section 8): `undefined`, `null`,
boolean, number (a `Double`), string, and object. Objects are references. Everything else is copied.
`MovieClip` and the other display classes are ordinary objects that report a different `typeof`.

Value equality is strict equality (`ActionStrictEquals`, ECMA-262 11.9.6): same type, same value,
objects by identity, NaN not equal to itself, and `-0` equal to `0`.

`typeof` differs from ECMAScript in two places: `typeof null` is `"null"`, not `"object"`, and an
object can override its answer, so a clip reports `"movieclip"`.

## Coercions

`ToPrimitive` needs to call `valueOf` and `toString` on an object, so it lives on the interpreter.

| Rule | Reference | Notes |
| --- | --- | --- |
| `ToBoolean` | ECMA-262 9.2 | Empty string is false from SWF 7. Earlier versions use "reads as a non-zero number" |
| `ToNumber` | ECMA-262 9.3, 9.3.1 | Plus the ActionScript `0x` hex form. `undefined` is NaN from SWF 7, and 0 before |
| `ToString` | ECMA-262 9.8, 9.8.1 | `undefined` is `"undefined"` from SWF 7, and `""` before |
| `ToInt32`, `ToUint32` | ECMA-262 9.5, 9.6 | Done in `Double`, so infinite and out-of-range inputs cannot trap |
| Abstract equality | ECMA-262 11.9.3 | `null == undefined`, but `null == 0` is false |
| Strict equality | ECMA-262 11.9.6 | Value equality |
| Relational | ECMA-262 11.8.5 | Two strings compare by UTF-16 code unit. Anything else is numeric, and NaN gives false |
| `ActionAdd2` | ECMA-262 11.6.1 | Both sides become primitives first. A string on either side makes it a join |

Two rules depend on the SWF version, so coercion carries a version. The default is SWF 9, which is
what vanilla Scaleform menus are published at.

Number formatting follows ECMA-262 9.8.1: a whole number below 1e21 prints in full
(`100000000000000000000`). Everything else uses Swift's shortest round-trip form with the exponent
spelled the ECMAScript way (`1e+21`, `1e-7`). That last step only approximates the spec's digit
algorithm.

## Objects

An object has a property table in insertion order, a `__proto__` link, and attributes per property.

- Attributes: don't enumerate, don't delete, and read only, matching the bits `ASSetPropFlags`
  sets. That function is an undocumented Flash built-in, so the bit values are as observed.
- Accessors: a slot can hold a getter and setter pair. `Object.prototype.addProperty` installs one.
  The `__get__name` and `__set__name` names the ActionScript 2 compiler emits for class properties
  are used as a fallback after the normal lookup misses.
- Arrays: array elements live in the ordinary property table under their decimal names, as ECMAScript
  says. `length` is made on read and cuts the array on write.
- Prototype walks stop after 64 steps, so a `__proto__` cycle in broken bytecode cannot hang a lookup.
- Host payload: an opaque engine object. The interpreter never looks inside, but its presence sends
  an unresolved member to the host. Display objects attach here.

A function is an object with either a Swift closure or a bytecode body. A bytecode function does not
own its bytes: the `ActionDefineFunction` header gives a `codeSize`, and the body is the next
`codeSize` bytes of the same stream. So the function keeps its block and start offset, its scope
chain, its constant pool, and the target it was defined under.

`ActionExtends` builds the bridge prototype Flash builds: a new object whose `__proto__` is the
superclass prototype, with `constructor` and `__constructor__` naming the superclass, installed as
the subclass's `prototype`. `super` is then a binding object whose prototype is the superclass
prototype and which binds `this` back to the original receiver. So both `super.method()` and a bare
`super(...)` call work from one object.

## Where super starts

A `super` built from `this.__proto__` is only right one level deep. `this` stays the same while a
constructor chain runs, so the base constructor's `super` pointed at the constructor it was just
called through, and it called itself until the depth limit stopped it. Three levels is the vanilla
shape: a CLIK component extends `gfx.core.UIComponent`, which extends `MovieClip`. Before this was
fixed, the install's movies raised 394 depth faults. Now they raise none.

So each frame records the prototype of the class whose method it runs, taken from the call that
started it:

- `new C()`: the constructor's own `prototype`.
- `obj.method()`: the prototype the method was found on. If the receiver owns the slot itself, the
  receiver's prototype is the fallback.
- A call through a `super` binding: the superclass prototype the binding recorded, so the next
  `super` starts one level higher.

Only the class's own `__constructor__` names its superclass. The inherited one names the wrong
parent. The frame's class is set before parameters are bound, because `ActionDefineFunction2`'s
`PreloadSuper` builds the `super` register then, and vanilla constructors call `super()` through that
register.

A method stored on the instance itself, not a class prototype, has no class to start from, and falls
back to the receiver's prototype. No vanilla movie does this in a `super` chain.

## Running bytecode

The runtime holds `_global`, the built-in prototypes, class registrations, limits, the tally, and the
trace log. An interpreter is made per call, and holds only its budget and depth.

The loop walks the block's records by index. A branch turns its byte target back into an index. A
function body is an index range in the same block, so return and branch work the same at any depth.
A branch into the middle of a record, or outside the running body, is a fault, not operand bytes read
as opcodes.

Calls run on the interpreter's own frame stack, not the Swift stack. Each frame has its record range
and instruction pointer. Calling a bytecode function pushes a frame, and popping it sends the value
to the caller's operand stack, or, for `new`, gives the constructor's returned object or else the new
instance. Swift recursion is used only when a value must come back inside a Swift call: a built-in
calling bytecode (`Function.prototype.call` and `.apply`) and a property accessor. That path has its
own small depth limit, because it is the one that uses Swift stack.

Names resolve from the innermost scope out, then `this`, then `_global`. Assigning an undeclared name
writes to the timeline target, not the innermost scope: that is ActionScript, not ECMAScript.

A dotted name walks members from its first part first, so `gfx.controls.Button` reaches
`_global.gfx.controls.Button`. Only if that misses does the display path resolver try it, which owns
slash paths and `..`. The order was measured: resolving display paths first made every qualified
class name in the vanilla CLIK library miss.

`ActionDefineFunction2` fills preload registers from register 1 up in the spec's order: `this`,
`arguments`, `super`, `_root`, `_parent`, `_global`. `suppressThis` and `suppressSuper` are ignored,
because `this` and `super` come from the frame.

`ActionCallFunction` binds `this` to the calling frame's `this`. Flash binds it to the target clip
when the name did not resolve on an object. The two agree for timeline code and can differ in a
method. There is no `with` scope, because no vanilla movie uses `ActionWith`.

## Bounds

Bytecode comes from the user's game files, and nothing checks it first. So every call runs under
limits, and each way a stream can be wrong ends in a recorded fault that stops that call and nothing
else. A faulted block leaves the runtime usable.

| Limit | Default | Why |
| --- | --- | --- |
| Action budget | 1,000,000 | Shared by every nested call. The largest vanilla block has 5,886 records, so this leaves room for loops and still stops a runaway in under a second |
| Call depth | 256 | Calls use the interpreter's own stack, so this is a policy. It matches Flash's 256-frame default |
| Re-entry depth | 32 | Nested Swift calls back into bytecode, the only path that uses Swift stack |
| Stack depth | 4,096 | Flash compiles expressions, not unbounded stack machines |
| Registers | 256 | The `ActionDefineFunction2` field is a `UInt8`. The deepest vanilla function uses 23 |

Reading an empty stack is not a fault. Flash gives `undefined` and goes on, and vanilla depends on
it: the compiler emits an `ActionPop` at a join point that both sides of a branch reach with an empty
stack. That happens in 666 of the 1,180 vanilla action blocks. It is counted instead.

## The tally

An unimplemented opcode or an unknown API is a logged no-op plus a tally entry, never an error. The
tally counts unimplemented opcodes (ranked, with Adobe names), missing names (ranked), faults, empty
stack reads (normal, so they do not make a run unclean), and actions, blocks, and calls run. Name
tables keep at most 256 names, and totals keep counting past that. `ActionTrace` output goes to a
bounded trace log, never to `print`.

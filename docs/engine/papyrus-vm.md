---
type: Engine Subsystem
title: Papyrus virtual machine
description: Bounded execution of Skyrim PEX functions with explicit frames,
  typed values, native registry, deterministic scheduling and tallies, driven
  once per frame from the engine loop with a script event queue and save state.
tags: [engine, papyrus, virtual-machine, bytecode]
timestamp: 2026-07-30T00:00:00Z
---

# Papyrus virtual machine

OpenSky executes the typed instructions produced by the
[PEX decoder](/formats/pex.md) in a Skyrim Papyrus virtual machine.
`PapyrusRuntime` owns the script library, attached instances, opaque object
handles, native registry, limits and tally. `PapyrusInterpreter` is created for
one invocation and owns its remaining instruction budget and explicit frame
stack. `PapyrusScheduler` advances suspended calls only from injected fixed
steps and game-clock samples.

Those three types are nonisolated and know nothing about the world. The
main-actor `PapyrusWorldRuntime` is what puts one of them inside the engine
loop: it owns per-reference script instances, a single FIFO event queue, and a
budgeted fixed-step tick driven once per drawn frame. Everything from
[World runtime and confinement](#world-runtime-and-confinement) onwards
describes that world-side layer.

Language semantics come from the Creation Kit wiki:

* [Papyrus category](https://ck.uesp.net/wiki/Category:Papyrus);
* [Literals Reference](https://ck.uesp.net/wiki/Literals_Reference);
* [Operator Reference](https://ck.uesp.net/wiki/Operator_Reference);
* [Differences from Previous Scripting](https://ck.uesp.net/wiki/Differences_from_Previous_Scripting);
  and
* [States (Papyrus)](https://ck.uesp.net/wiki/States_(Papyrus)).

The PEX instruction shapes and opcode numbers come from
[UESP, Compiled Script File Format](https://en.uesp.net/wiki/Skyrim_Mod:Compiled_Script_File_Format).
The public references leave some virtual-machine behavior unspecified. Every
choice OpenSky makes in those gaps is listed under [Deviations](#deviations).

## Contents

* [Values and types](#values-and-types)
* [Runtime and instances](#runtime-and-instances)
* [Frames and execution](#frames-and-execution)
* [Calls and suspension](#calls-and-suspension)
* [Native registry](#native-registry)
* [Deterministic scheduler](#deterministic-scheduler)
* [Properties and arrays](#properties-and-arrays)
* [States](#states)
* [Bounds and faults](#bounds-and-faults)
* [Tally](#tally)
* [World runtime and confinement](#world-runtime-and-confinement)
* [Frame hook and fixed step](#frame-hook-and-fixed-step)
* [Event queue](#event-queue)
* [Activation and the world bridge](#activation-and-the-world-bridge)
* [Instance lifecycle over cell streaming](#instance-lifecycle-over-cell-streaming)
* [Script state in a save](#script-state-in-a-save)
* [Lazy script library](#lazy-script-library)
* [Tests](#tests)
* [M11.1 acceptance](#m111-acceptance)
* [A script changing the world, end to end](#a-script-changing-the-world-end-to-end)
* [Deviations](#deviations)
* [Scope](#scope)

## Values and types

`PapyrusValue` represents `None`, `Bool`, signed 32-bit `Int`, IEEE-754
binary32 `Float`, `String`, an opaque `PapyrusObjectHandle`, and a
reference-semantic `PapyrusArray`. `PapyrusType` parses PEX type names,
including the `Type[]` spelling, and provides the declared default:

| type | default |
| --- | --- |
| `None` | `None` |
| `Bool` | `False` |
| `Int` | `0` |
| `Float` | `0.0` |
| `String` | empty string |
| object | `None` |
| array | `None` |

Arrays retain their declared element type and are shared by reference, so a
callee mutating an array changes the caller-visible object. Arrays of arrays and
Fallout 4 structs are not represented.

`PapyrusCoercion` implements the documented truth rules: zero numbers, empty
strings, `None`, and empty arrays are false; non-zero numbers, non-empty
strings, object handles, and non-empty arrays are true. Numeric conversion
accepts booleans and numeric strings, including the Papyrus `0x` integer form.
String conversion covers every value kind.

## Runtime and instances

`PapyrusRuntime` indexes every `PexObject` in its input files by a
case-insensitive script name. `makeInstance(scriptName:handle:initialValues:)`
allocates or accepts an opaque handle, builds child-to-parent variable storage,
and starts the instance in the root script's automatic state.

An object handle does not need a `PapyrusInstance`. VMAD may inject a world
object whose scripts are not loaded into this runtime; a method call on that
handle goes directly to native dispatch and uses the receiver identifier's
declared Papyrus type as the call's script name.

Variables are stored under the script that declared them. A child and parent
may therefore each own a private variable with the same name, and a function
reads the scope of its declaring script. The injectable initial-values table
uses source variable names and replaces the first child-to-parent match after
checking the declared type. This is the VMAD property-value attachment seam;
the interpreter itself does not know how those values were decoded. The
[VMAD decoder and binding bridge](/formats/vmad.md) resolves direct object
FormIDs and uses the exact automatic backing-variable name stored in PEX.

The runtime exposes instance and static entry points:

```swift
func invoke(
    _ functionName: String,
    on handle: PapyrusObjectHandle,
    arguments: [PapyrusValue] = []
) -> PapyrusRunOutcome

func invokeStatic(
    _ functionName: String,
    on scriptName: String,
    arguments: [PapyrusValue] = []
) -> PapyrusRunOutcome

func resume(
    _ suspendedCall: SuspendedCall,
    returning value: PapyrusValue? = nil
) -> PapyrusRunOutcome
```

The outcome is exactly one of `.completed(PapyrusValue)`,
`.faulted(PapyrusFault)`, or `.suspended(SuspendedCall)`.

## Frames and execution

`PapyrusFrame` holds the function, declaring script, optional instance handle,
typed parameters and locals, instruction pointer, and completion action. A
completion either returns the root result, assigns a callee result into the
calling frame, or discards a setter result.

The execution loop increments the caller instruction pointer before it executes
an instruction. A PEX relative branch therefore adds its signed offset to the
next instruction index. The target may equal the function's instruction count,
which completes the function with its declared default; another out-of-range
target faults.

All 36 Skyrim PEX opcodes execute:

| group | opcodes |
| --- | --- |
| scalar | `nop`, assign, cast, return, not and numeric negation |
| integer math | add, subtract, multiply, divide and modulo |
| float math | add, subtract, multiply and divide |
| comparison | equal, less, less-or-equal, greater and greater-or-equal |
| control | jump, jump-true and jump-false |
| calls | method, parent and static |
| members | property get and set |
| strings | concatenate |
| arrays | create, length, get, set, find and reverse-find |

Integer add, subtract, multiply and negation use two's-complement wrapping so
hostile operands cannot trap Swift. Division widens to 64 bits before narrowing,
which also handles `Int32.min / -1` without a process crash.

## Calls and suspension

A bytecode call pushes a frame onto the interpreter-owned array. It never calls
another PEX function through Swift recursion. The frame completion assigns the
return value after the callee is popped, then the same loop continues the
caller.

Method lookup starts from the receiver's attached root script. `callparent`
starts at the parent of the function's declaring script. Static calls target
the named script's empty-state function. A native flag or a call with no
decoded PEX body routes to `PapyrusNativeDispatch`.

`PapyrusNativeRegistry.standard` is the runtime default. A registered function
returns a value, a reason-tagged failure, a suspension request, or an explicit
deviation. An unknown `(script, function)` pair is logged and tallied, then
returns the destination's declared default. A native argument failure follows
the same default-return policy and retains its reason in the tally. This keeps
vanilla scripts moving without inventing world state or treating every unknown
native as success.

A suspension retains the native request, frames, pending destination and
remaining instruction budget. `resume(_:returning:)` consumes that continuation
once. With no explicit value it assigns the suspended call's declared default;
a host may instead provide a value. A second resume faults.

`PapyrusRecordingNativeDispatch` remains available to tests and hosts that need
to queue native results and inspect a bounded call tail.

## Native registry

`PapyrusNativeRegistry` keys functions case-insensitively by both script and
function name. `.empty` installs nothing. `.standard` installs 37 entries in
one place:

| family | functions | headless policy |
| --- | --- | --- |
| `Debug` | `Trace`, `MessageBox` | append to a bounded log and unified logging |
| `Utility` | `Wait`, `WaitGameTime`, `RandomInt`, `RandomFloat` | suspend on the injected clock or use a seeded generator |
| `Math` | `Abs`, `Floor`, `Ceiling`, `Sqrt`, `Pow`, `DegreesToRadians`, `RadiansToDegrees`, `Sin`, `Cos`, `Tan`, `Asin`, `Acos`, `Atan` | deterministic binary32 calculation |
| `ObjectReference` animation | `PlayAnimation`, `PlayAnimationAndWait`, `PlayGamebryoAnimation` | return true immediately, log and tally the deferred-animation deviation |
| `ObjectReference` world | `Enable`, `Disable`, `IsEnabled`, `Delete`, `GetPositionX`, `GetPositionY`, `GetPositionZ`, `SetPosition`, `Activate`, `GetLinkedRef` | fail with an invalid-arguments reason; the interpreter substitutes the declared default and the script continues |
| `GlobalVariable` | `GetValue`, `GetValueInt`, `SetValue`, `SetValueInt` | same failure policy |
| `Game` | `GetPlayer` | same failure policy |

The corpus census found no string native that can be answered honestly without
world context, and string basics are PEX opcodes rather than natives, so they
remain visible unknowns instead of receiving plausible-looking stubs.
Animation graph behavior belongs to M14. Until then the three animation calls
are the sole intentional success-without-effect family, and every occurrence is
measurable.

`PapyrusNativeContext` owns the seeded random source and bounded debug log.
Tests can inject a seed and assert exact sequences without reading a host clock
or global random generator.

### The three world families

The last three rows are the natives that reach the world through
[the world bridge](#the-world-bridge), and they share one policy. Each takes
its `self` from `PapyrusNativeCall.receiver` and turns it into a
`ReferenceKey`; a headless runtime, a receiver no world runtime handed out, or
a missing receiver is a failure with a reason rather than a guess. Every
mutation is one `WorldStateStore` write, attributed to the reference's resident
cell so the rebuild fan-out stays narrow.

A write never requires the reference to be resident — a script may disable
something in a cell nobody has streamed, and the delta waits in the store. A
read that needs the plugin baseline (`IsEnabled`, the position getters, and
`SetPosition`, which preserves the rotation, the XSCL scale and any axis it is
not given) does require it, because there is nothing honest to answer with
otherwise.

`GetLinkedRef` resolves the REFR's decoded `XLKR` list: with a keyword the
first link tagged with it, with `None` the first untagged link. Every "no
answer" case returns `PapyrusValue.none`, which is what Papyrus `None` is and
what the interpreter would substitute for a failed object-returning call.
Because `XLKR` stores its keyword as a load-order-relative FormID while the
argument arrives as world identity, each candidate tag is resolved through the
session's master-list resolver and compared as a `ReferenceKey`; a tag this
session cannot name never matches.

`Activate` is `activate(_:by:togglesOpen:)` and nothing else: it never re-runs
the interaction raycast. The activator is argument 0, falling back to the
player for an absent argument, for `None`, and for a handle with no world
identity. It returns false only when the recursion cap refused the activation.

`GlobalVariable` writes go through `WorldStateStore.setGlobal(_:formID:defaults:)`,
so `Global.ValueType.coerce` rounds a short or long global on every write.
`GetValueInt` truncates toward zero and saturates at the `Int32` bounds. The
reads fail for a key this session defines no global for, because zero is a
value a script would act upon; the writes do not, because in a session with no
`GlobalStore` the first write is what creates the override.

`Game.GetPlayer` answers with the opaque handle for
[`ReferenceKey.player`](#the-players-referencekey), stable for the session, so
the usual `akActionRef == Game.GetPlayer()` guard works.

### Stated simplifications and gaps

| behavior | what OpenSky does | why |
| --- | --- | --- |
| `Enable(abFadeIn)`, `Disable(abFadeOut)` | argument accepted and ignored | M11 has no fade; the reference appears or disappears on the next cell rebuild, and the state written is identical either way |
| `Activate(_, abDefaultProcessingOnly)` | argument accepted and ignored | there is no built-in activation behavior on this path to restrict the call to |
| `Activate` and `isOpen` | never toggles it | only the player's use key knows the interaction was an `open` action; a script-side `Activate` records the activation without claiming the target opened |
| `TranslateTo`, `TranslateToRef`, `SplineTranslateTo` | not installed | interpolated motion and `OnTranslationComplete` need a mover the world runtime does not have; deferred to a later milestone rather than stubbed into looking successful |
| `XESP` enable-parent chains | not decoded | `Enable` and `Disable` act on the receiver alone, so a reference enabled by a parent stays as the plugin authored it. A documented gap for M18+ |
| `Global.isConstant` | recorded, not enforced | the Creation Kit's rule forbids *editing* a constant global in the editor, which is about authored data; no open documentation says the engine refuses a scripted write, so one is applied and recorded like any other |
| `Delete` | writes the delta unconditionally | the Creation Kit documents `Delete` as taking effect only once nothing holds the reference; OpenSky has no reference counting yet |

## Deterministic scheduler

`PapyrusScheduler` accepts a fixed real-time step and sampled `GameClock`
values. `Utility.Wait` wakes after a counted whole number of fixed steps, as
[Frame hook and fixed step](#frame-hook-and-fixed-step) explains;
`Utility.WaitGameTime` wakes after accumulated forward game hours. The first
game-clock sample establishes the baseline. A backward clock scrub contributes
zero elapsed game time, while a forward jump is capped at 24 game hours per
tick by default. This prevents a settings scrub from releasing an unbounded
latent queue.

Calls due on the same tick resume in registration order. A resumed call may
suspend again and remains ordered by its new registration. The scheduler never
reads wall-clock time, so identical inputs produce identical outcomes.

## Properties and arrays

Automatic properties read and write their compiler-generated backing variable
in the declaring script's private storage. Non-automatic getters and setters
push their decoded handler bodies as ordinary frames. A missing accessor,
backing variable, property or receiver is a typed fault.

Array creation derives the element type from the typed destination, fills each
element with that type's default, and rejects negative or over-limit lengths.
Get and set enforce bounds. Set coerces to the declared element type.
Find searches forward from `max(0, start)`; reverse-find treats a negative start
as the last element and otherwise clamps it to the last valid index. Both
return `-1` when no element matches.

## States

Each instance has one case-insensitive active state. Function resolution follows
the Creation Kit wiki's four priorities:

1. the derived script in the active state;
2. each parent script in the active state;
3. the derived script in the empty state; and
4. each parent script in the empty state.

`GotoState` and `GetState` are VM intrinsics when called as methods on an
attached instance. `GotoState` changes the active-state spelling immediately
and the current function continues. Later calls observe the new state.

## Bounds and faults

Every invocation uses `PapyrusLimits`:

| limit | default | purpose |
| --- | ---: | --- |
| instruction budget | 1,000,000 | bounds loops and all nested calls |
| call depth | 256 | bounds the explicit frame stack |
| inheritance depth | 64 | bounds parent walks and detects cycles |
| array length | 100,000 | bounds allocation and linear searches |
| tally names | 256 | bounds distinct native-call names |
| fault records | 64 | bounds retained fault detail |
| native-call records | 1,024 | bounds the recorder tail |

`PapyrusFault` covers budget exhaustion, call-depth exhaustion, invalid jumps,
type mismatch, unknown opcodes, malformed operands, divide by zero, array
bounds and allocation limits, missing functions, properties and instances,
inheritance cycles, and invalid resume. The runtime reports faults as values and
remains usable; no execution-path force unwrap, force cast, or force try exists.

## Tally

`PapyrusTally` is owned by the runtime and survives invocations. It keeps run
and instruction totals, per-opcode counts, native calls, unknown natives,
native failures, deferred animations, suspensions, fault kinds, and a bounded
fault tail. Totals are uncapped while every attacker-controlled name table has
the `PapyrusLimits.tallyNames` cap. `PapyrusTallySnapshot` is an equatable,
sendable first-class acceptance result with stable ranked accessors.

## World runtime and confinement

`PapyrusWorldRuntime` (`opensky/Papyrus/PapyrusWorldRuntime.swift`) is the
`@MainActor` class that owns one `PapyrusRuntime`, one `PapyrusScheduler`, and
the world-side bookkeeping the headless core deliberately has none of. Its
confinement model is the same as
[`WorldStateStore`](/engine/runtime-state.md): every field is main-actor state,
written and read on the thread that runs `draw(in:)`, so nothing between a
streamed cell and the script attached to it needs a lock or an actor hop. The
M11.1 `PapyrusRuntime` was not renamed and not changed in shape; it is still
the script library and instance table underneath.

The implementation splits across satellites by concern:
`PapyrusWorldState.swift` holds the value types,
`PapyrusWorldEvents.swift` the tick and dispatch,
`PapyrusWorldLifecycle.swift` cell attach and detach, and
`PapyrusWorldPersistence.swift` the save snapshot and restore.

| type | what it is |
| --- | --- |
| `PapyrusInstanceKey` | world identity of one instance: a `ReferenceKey` plus the lowercased script name. `Comparable`, ordering by reference then script name, which is what makes attach order, event order and save bytes deterministic |
| `PapyrusVariableState` | one persisted variable: lowercased declaring script, lowercased name, and a `PapyrusValue` |
| `PapyrusInstanceState` | one instance's persisted state: key, active state, sorted variables, and whether `OnInit` has fired |
| `PapyrusScriptEvent` | one queued event: target instance, function name, arguments |
| `PapyrusTickBudget` | per-tick ceiling, 32 events and 100,000 instructions by default |
| `PapyrusTickReport` | what one tick did: `steps`, `dispatched`, `queued`, `resumed`, `faulted` |
| `PapyrusWorldSkipReason` / `PapyrusWorldSkipTally` | counted, non-fatal skips, ranked the same way `ScriptBindingTally` is |

The budget defaults bound one 1/30 second step rather than throughput. A cell
attach enqueues three events per instance, so 32 events drains a ten-script
cell in a single step while a mass attach carries over instead of hitching the
frame. The 100,000-instruction ceiling is a tenth of
`PapyrusLimits.instructionBudget`, so one runaway handler cannot consume more
of a frame than a single whole invocation is allowed to consume in total.

Skips are counted, never faults, because malformed or unrecognised input must
not stop the world:

| reason | raised when |
| --- | --- |
| `removedScript` | the VMAD entry is flagged removed |
| `missingScript` | the script name is not in the library and cannot be loaded |
| `instanceCreationFailed` | `makeInstance` threw |
| `bindingFailed` | a VMAD property could not be bound onto the instance |
| `retiredEventTarget` | an event's instance was retired before it was dispatched |
| `undefinedEventFunction` | the script chain defines no such function |
| `unknownSaveScript` | a `PSCR` entry names a script this session cannot instantiate |
| `unknownSaveVariable` | a `PSCR` variable does not exist on the restored instance |

## Frame hook and fixed step

`Renderer.onWorldUpdate: ((Float) -> Void)?` is the engine seam, invoked once
per drawn frame from `updateWorldSimFromWallClock()` in `RendererDraw.draw(in:)`.
The order inside a frame is `advanceCamera()`, then `onFrame(position)` (cell
streaming and the HUD), then `advanceGameClockFromWallClock()`, then
`updateWorldSimFromWallClock()`, then the weather, animation, particle and
audio updates. The world tick runs after the game clock advances on purpose, so
a script waking on game time sees this frame's clock rather than the previous
frame's.

Wiring a second subscriber to that frame revealed a real hazard beside it.
`Renderer.onFrame` had been a single optional closure, and both
`GameViewControllerStreaming.swift` and `wireHUDFrameUpdates(renderer:)` wanted
it, so the second assignment silently dropped the first. It is now a
`CallbackFanOut<SIMD3<Float>>` (`opensky/World/CallbackFanOut.swift`): an
ordered list of handlers delivered in registration order, with no removal, no
identity and no thread hand-off, because every engine callback is wired once at
setup and fired on the thread that drives `draw(in:)`. `wireHUDFrameUpdates` is
registered after `startStreaming`, so delivery order stays streamer first and
HUD second, exactly as it behaved when streaming owned the only assignment.
`CellStreamer.onInteraction` was deliberately left a single-assignment closure.

Menu pause reaches the VM through a clock, never through a branch around the
call. `Renderer.worldSimClock` is a `FrameSimClock` advanced with
`paused: worldSimPaused` (see [menu mode](/engine/menu-mode.md)), so a paused
frame delivers a delta of exactly zero and the hook still fires. The world
runtime itself never reads the wall clock and never inspects a pause flag.

Two entry points consume that delta:

```swift
func stepFixed(gameClock: GameClock? = nil) -> PapyrusTickReport
func advance(delta: Float, gameClock: GameClock? = nil) -> PapyrusTickReport
```

`stepFixed` advances exactly one fixed step: it ticks the scheduler, settles
whatever woke, then drains the event queue up to the budget. It is fully
deterministic and is what tests and the offscreen path drive.

`advance` accumulates a wall delta into a fixed-step accumulator and runs whole
steps only, so a variable frame rate never changes the simulation. A delta of
zero or less returns immediately, having advanced nothing, which is the paused
case. One call runs at most `PapyrusWorldRuntime.maximumStepsPerAdvance` (4)
steps, and afterwards the accumulator is clamped to four steps' worth of
seconds, so a multi-second stall cannot spiral into minutes of catch-up
simulation on later frames.

`RendererOffscreen` calls `onWorldUpdate?(simDelta)` with the same fixed
`1 / 30` step it already uses for animation, inside the `advanceAnimation`
block and subject to the same `worldSimPaused` gate. The offscreen path still
never advances the game clock, so an offscreen bench or test drives the VM
deterministically.

`PapyrusScheduler` changed to make that fixed step exact. A real-time wake now
records the tick it was enqueued on and compares whole ticks since
(`Wake.realSteps(startTick:duration:)`) instead of accumulating a `realSeconds`
double. Accumulating 1/30 thirty times drifts past 1.0, so `Utility.Wait(1.0)`
used to wake on the 31st step; the multiplicative form
`Double(tickCount - startTick) * fixedStepSeconds` wakes on exactly the 30th.
`realSeconds` survives as a computed property over `tickCount`. The scheduler
also gained an `onResume` observation seam, called after every woken call
resumes and before its outcome is routed, which is how the world runtime tracks
per-instance busy state across a re-suspension.

## Event queue

There is one event queue for the whole world: a main-actor FIFO array on
`PapyrusWorldRuntime`. Global order is preserved — an event enqueued earlier is
dispatched no later than one enqueued after it — and events are enqueued, never
dispatched inline, so an attach never re-enters the VM from inside streaming.

Delivery is serial per instance. An instance that suspends in a latent call is
marked busy (`busyInstances`, maintained through
`PapyrusWorldSuspensionTracker` and the scheduler's `onResume`), and its
further events stay queued, in order, until the suspended handler settles.
Other instances keep running past it. A skipped busy-instance event is put back
ahead of the untouched tail, so the queue never reorders itself.

A drain stops when the tick's event budget is spent or when the instructions
executed since the drain began exceed the tick's instruction budget. Whatever
is left carries over to the next tick and is reported as `queued`.

Three outcomes are counted no-ops rather than faults, because none of them is a
malformed program:

* the target instance was already retired (`retiredEventTarget`);
* the event is a repeat `OnInit` for an instance that already fired one; and
* the script chain does not define the function at all
  (`undefinedEventFunction`), which is the common case — most scripts implement
  a handful of the events the engine offers.

Function definition is tested through `PapyrusInterpreter.resolveMethod`, the
same resolution the interpreter itself uses, so state priority is respected.

`OnInit` fires once ever per instance. `firedOnInit` records that fact and
persists in the save; `pendingOnInit` covers the window between enqueue and
dispatch so a rebuild in between cannot enqueue a second one.

## Activation and the world bridge

Issue #172 connects the player's use key to script code and opens the seam every
world-touching native reaches the engine through. Four decisions carry it.

### The player's `ReferenceKey`

The player is not a plugin reference in this engine: no record is decoded for it
and no cell streams it. It still needs one session-stable identity, because it
is the activator recorded in `ReferenceActivationState.lastActivator` and the
`akActionRef` script code receives.

`ReferenceKey.player` is that identity, and it is `.generated(0)`.
`GeneratedReferenceAllocator` starts at 1 and documents 0 as reserved, so the
sentinel can never collide with an allocated key; it sorts after every plugin
key, needs no plugin loaded, and round-trips through the save file's
generated-key tag unchanged. Using the vanilla `Skyrim.esm:000014` player
reference was rejected: it names a record OpenSky does not decode, it would be
wrong for any load order without that plugin, and it would make the player look
like an ordinary streamed reference the cell builder might try to draw. The
constant lives on `ReferenceKey` so no call site spells the sentinel out.

Nothing resolves a `RuntimeReferenceEntry` for the player, so a component
written under this key is bookkeeping only — it is an activator identity and a
handle identity, not something that can be drawn.

### `OnActivate` and `akActionRef`

`PapyrusWorldRuntime.queueOnActivate(target:activator:)` enqueues one
`PapyrusScriptEvent` per script instance attached to the activated reference,
iterating `instancesByKey` in `PapyrusInstanceKey` order so the queue is
deterministic. The function name is `onActivateEventName` (`"OnActivate"`) and
argument 0 is the activator as `PapyrusValue.object(handle)`, matching
`OnActivate(ObjectReference akActionRef)`. A target carrying no scripts queues
nothing and is not an error; the activation is still recorded.

The activator needs a handle even when it has no script instance, which is
exactly the player's case. `PapyrusWorldRuntime.objectHandle(for:)` answers with
the live instance handle when the reference carries scripts — the same handle
VMAD object properties bind to — and otherwise mints an opaque handle, cached so
it is stable for the session. Opaque handles are allocated downwards from
`UInt64.max` while `PapyrusRuntime` allocates instance handles upwards from 1,
which is what keeps the two ranges apart. `referenceKey(for:)` resolves either
kind back to a `ReferenceKey`. A handle with no instance behind it still
dispatches natives correctly, because the interpreter takes the script name from
the operand's declared type.

Stated edge: a reference that gains a script instance after an opaque handle was
handed out keeps both handles. Both resolve to the same `ReferenceKey`, so world
writes stay correct; only handle-identity comparison inside script code could
notice.

### The world bridge

Native bodies are nonisolated and `@Sendable`; `WorldStateStore` and
`PapyrusWorldRuntime` are `@MainActor`. The seam that reconciles the two is in
`opensky/Papyrus/PapyrusWorldBridge.swift`:

| Type | Isolation | Role |
| --- | --- | --- |
| `PapyrusWorldBridge` | `@MainActor` protocol | every world operation a native may perform |
| `PapyrusWorldStateBridge` | `@MainActor` class | the production conformer, over `WorldStateStore` |
| `PapyrusWorldAccess` | nonisolated class | the façade a native holds, as `context.world` |
| `PapyrusWorldReferenceSource` | nonisolated protocol | decoded references and their resident cell |

The protocol covers handle-to-key and key-to-handle resolution, the resolved
`ReferenceState`, the decoded `PlacedReference` behind a key, the cell a
reference is resident in, one component write, global read and write, and
`activate(_:by:togglesOpen:)`. Every mutation goes through
`WorldStateStore.set(_:for:in:)` or `setGlobal(_:formID:defaults:)` — nothing
writes around the store, so the journal, the dirty counts and the save all see
it. Writes carry the reference's resident cell when the source knows it, which
narrows the rebuild fan-out to that one cell.

`PapyrusWorldAccess` mirrors the protocol one-for-one and hops with
`MainActor.assumeIsolated`. That is an assertion rather than a suppression: a
native reached off the main actor traps instead of racing, and native bodies are
only ever run synchronously from the world runtime's tick, which is on the main
actor. `@unchecked Sendable` and a global mutable were both rejected.

A headless runtime leaves `PapyrusNativeContext.world` nil, so every native
access is optional and a world-needing native fails cleanly instead of guessing.
The world-aware session is built by `PapyrusNativeRegistry.standard(context:)`
with a context carrying the access façade, and installed at
`GameViewControllerPapyrus.wirePapyrus` where the runtime is constructed.
Ownership runs one way: the registry inside the runtime owns the bridge, so the
bridge holds the runtime and the streamer weakly.

`PapyrusWorldStateBridge.handleInteraction(_:)` is the `onInteraction`
subscriber described in [interaction](/engine/interaction.md). It maps the
event's `FormID` to a `ReferenceKey`, records
`ReferenceActivationState.activated(by:togglesOpen:)` with the player as
activator — `togglesOpen` set only for a door-style `open` action — and queues
the target's `OnActivate`. This is that method's first production caller.

### The activation recursion cap

A script activating a reference whose `OnActivate` activates it back would
ping-pong forever, one round per tick, because events are queued rather than
dispatched inline. Each `PapyrusScriptEvent` therefore carries an
`activationDepth`: a player use key queues at depth 1, an activation performed
while dispatching a depth-*n* event queues at depth *n+1*, and every other event
stays at 0. `PapyrusWorldRuntime.maximumActivationDepth` is 8; past it nothing is
queued, no activation is recorded, and `PapyrusTally.noteActivationRecursionCapped`
increments `activationRecursionCappedTotal`, which
`PapyrusTallySnapshot` carries.

Stated simplification: a latent handler that resumes on a later tick has lost the
depth of the event that started it and re-enters at 0. The per-tick event budget
still bounds what that can cost in one frame.

## Instance lifecycle over cell streaming

`CellStreamer` gained two engine-level announcements and no dependency on the
VM at all:

```swift
var onCellAttached: ((CellScene, Bool) -> Void)?
var onCellDetached: ((CellSceneLocation) -> Void)?
```

The `Bool` is `firstIntegration`: true when the cell has genuinely joined the
live world, false when a cell that never left was merely re-integrated.
`CellStreamerPapyrus.swift` holds the emission helpers, and a scene with no
`CellSceneLocation` — a door destination whose CELL identity failed to resolve
— is not announced at all, since the location is the key a subscriber files
instances under. `GameViewControllerPapyrus.swift` is the only subscriber and
forwards to the world runtime, so every existing streaming test still runs
without a VM.

Four streaming paths needed a decision, each recorded at its call site in
[cell streaming](/engine/cell-streaming.md):

* An exterior integration reads `CellStreamCore.rebuilding` before
  `integrate` clears it, so a world-state rebuild attaches with
  `firstIntegration: false` and does not re-fire load events.
* A cell staged offscreen during a coverage transition announces nothing while
  it is staged; `commitCoverageTransition` promotes staged cells in sorted
  coordinate order and announces each one there, with `firstIntegration` true
  only when it did not replace a composed scene at the same coordinate.
  `discardStagedCells(outside:)` therefore emits no detach: a staged cell never
  emitted an attach.
* An interior door transition maps `CellStreamerTransitions.apply`'s `isRebuild`
  straight to `firstIntegration: !isRebuild`, and detaches the previous
  interior only when it is not a rebuild.
* The exterior branch of a door arrival detaches the previous interior but not
  the scene it replaces at the destination coordinate: that scene shares the
  arriving scene's `CellSceneLocation`, so detaching it would retire instances
  the attach immediately recreates.

`attach(cell:references:formIDResolver:firstIntegration:)` walks
`RuntimeReferenceIndex.sortedEntries()` for determinism and runs in two passes.
The first creates every missing instance in the cell; the second resolves VMAD
properties through the existing
`AttachedScript.binding(in:formIDResolver:objectHandle:)` and applies each
value with `PapyrusInstance.applyInitialValue(_:named:scriptChain:)`, once
every instance in the cell exists, so an object property naming a reference in
the same cell resolves to a live handle rather than to nothing. The
`objectHandle` closure is backed by `referenceHandleMap()`, which gives one
handle per reference; a reference carrying several scripts resolves to the
instance with the lowest script name. On a first integration each instance is
then given `OnInit` (only if it has never fired), then `OnCellAttach`, then
`OnLoad`, in that order.

`detach(cell:)` retires the cell's instances in sorted key order: the instance
leaves the runtime, its queued events are dropped, and its suspension
bookkeeping is forgotten.

## Script state in a save

`instanceStates()` returns every live instance's `PapyrusInstanceState`, sorted
by `PapyrusInstanceKey` with variables sorted by `(declaringScript, name)`, so
re-encoding an unchanged runtime is byte-identical.
`restore(instanceStates:)` reads them back, creating a missing instance from
the script library on demand, so restoring into a session that has attached no
cell yet works. An unknown script or variable is skipped and counted rather
than thrown.

The bytes live in the additive `PSCR` chunk of the
[OpenSky save container](/formats/opensky-save.md), which documents the
layout. `GameViewController.saveWorldState(slot:)` passes
`scripts: papyrus?.instanceStates() ?? []`.

`loadWorldState(slot:)` restores Papyrus **last**, after
`worldState.restore(from:)` and after the game clock. `worldState.restore`
fires one unattributed mutation, which only queues a rebuild for every resident
cell; those rebuilds re-attach on a later streaming update and consult
`firedOnInit` to decide whether to enqueue `OnInit`. Putting the saved fired
set in place before any rebuild attach can read it is exactly what stops every
script re-running its `OnInit` on load.

## Lazy script library

Decoding every `.pex` in an install up front costs far more than a session ever
uses, so the library fills in one script at a time:

```swift
var scriptProvider: ((String) -> PexFile?)?
```

`PapyrusWorldRuntime.resolveScript(named:)` asks the provider the first time an
attach needs a name, installs the result through the new
`PapyrusRuntime.register(_ file: PexFile)` (last writer wins), and remembers
every failure in `unresolvableScripts`, so a missing, truncated or
mod-authored-broken script is not re-decoded on every cell attach. A file that
decodes but does not contain the requested object counts as a failure too.

The app supplies the provider through a new `ScriptDataProviding` protocol on
the cell-scene provider, which exposes the shared
[`VirtualFileSystem`](/formats/vfs.md) and the master
[`FormIDResolver`](/formats/formid.md) — the same resolver every streamed
reference key came from, so a script and the cell it is attached to agree on
reference identity. `GameViewController.wirePapyrus` builds a
`PexScriptLoader` over that file system. A provider that is not
`ScriptDataProviding`, or one with no file system (a synthetic scene), leaves
`GameViewController.papyrus` nil rather than running a VM with an empty
library.

## Tests

All fixtures are assembled in Swift. `PexFixture` now builds direct runtime
models alongside its byte-level PEX builder; no compiler or game content is
needed.

The suite covers every opcode's happy path, primitive coercions, integer and
float behavior, relative branches, explicit method/parent/static frames,
automatic properties, every array operation, injected initial values, all four
state-resolution priorities, `GotoState`, native registry behavior, seeded
random results, real-time and game-time wake ordering, bounded recording, a
latent suspend/resume round trip, and the required budget, depth, bad-jump,
type-mismatch and unknown-opcode fault matrix.

The world layer is covered by its own device-free suites, all built on
`openskyTests/PapyrusWorldFixture.swift`, which assembles synthetic REFR
records with VMAD data, event scripts whose handlers record
`<script>.<event>` through a probing native dispatch, and a drain helper that
steps to quiescence:

* `PapyrusWorldRuntimeTests` — key ordering including case-insensitive script
  names, an instance-state round trip through a fresh unattached runtime that
  does not re-fire `OnInit`, object and array values snapshotting as `.none`,
  and a tolerant restore that counts one unknown script and one unknown
  variable.
* `PapyrusWorldLifecycleTests` — first-integration event order across two
  references, a silent rebuild that keeps the same handle, a reference newly
  appearing in a rebuild receiving only `OnInit`, detach clearing instances
  and queued events with no second `OnInit` on re-attach, and a persistent
  instance surviving detach with its variables intact.
* `PapyrusWorldEventQueueTests` — budget carry-over preserving global FIFO
  order across three ticks, per-instance serial delivery around a latent
  suspension, `Utility.Wait(1.0)` resuming after exactly 30 fixed 1/30 steps,
  a zero delta advancing nothing while staying safe every frame, partial
  deltas accumulating and a ten-second hitch capping at four steps, and an
  undefined event function counting as a no-op rather than a fault.
* `PapyrusWorldBindingTests` — VMAD properties binding across a cell, with an
  intra-cell object property resolving to the other reference's live handle,
  and removed and library-missing scripts counted rather than faulted.
* `CallbackFanOutTests` — zero handlers, delivery to every handler,
  registration order, a tuple payload, and a late handler joining only the
  next delivery.
* `CellStreamerPapyrusTests` — the streamer, a `WorldStateStore` and a world
  runtime wired exactly as `wirePapyrus` wires them, with no Metal and no game
  data: first integration, a world-state rebuild reconciling rather than
  recreating, unloading retiring instances, staged coverage cells attaching
  only when the transition commits, and an interior door arrival attaching
  where its rebuild does not.
* `RendererWorldSimTickTests` — Metal-4-gated, no game data: a latent wait
  resuming after the right number of fixed steps through a real `Renderer`, a
  partial delta advancing nothing until it accumulates a step, offscreen
  frames driving the tick, and a paused frame delivering zero so no script
  advances.
* `OpenSkySavePapyrusTests` — the `PSCR` chunk, described under
  [OpenSky save container](/formats/opensky-save.md).

## M11.1 acceptance

`PapyrusAcceptanceRealDataTests` ran through `make realtest` on 2026-07-30
against the user's read-only retail script corpus. It decoded 14,302 scripts,
resolved 65,477 typed native call sites from 686 native declarations, and
found 508 distinct referenced native pairs. The standard registry implements
18 of those 508 referenced pairs: **3.5% native coverage**. Four of its 22
entries are valid but not referenced by this corpus.

The same gate invoked all zero-argument `OnInit`, `OnLoad`, and
`OnPlayerLoadGame` functions in the empty state. All 577 entry points reached a
terminal outcome: 240 completed and 337 produced typed faults, with no pending
continuation or native argument failure. The run made 536 native calls,
returned declared defaults for 457 unknown calls, and recorded 18 deferred
animation deviations. Faults ranked as 231 `typeMismatch`, 93 `invalidJump`,
and 13 `invalidOperand`; the leading unknown was
`ObjectReference.GetLinkedRef` with 45 calls. The aggregate report is written
only to gitignored `logs/papyrus-m11-acceptance.log`.

M11.1 is explicitly headless in issue #170, so it has no sidebar destination,
control, or accessibility readout. The durable acceptance result is
`PapyrusTallySnapshot`, pinned by `M11AcceptanceTests`,
`PapyrusNativeRegistryTests`, `PapyrusSchedulerTests`,
`PexNativeCensusTests`, and the env-gated
`PapyrusAcceptanceRealDataTests`. M11.2 owns the discoverable
`World > Scripts` surface. This exception is also recorded in the
[sidebar acceptance ledger](/tools/sidebar-acceptance.md).

## A script changing the world, end to end

Issue #172's gate is one chain rather than a set of unit results, pinned by
`M11ScriptedWorldAcceptanceTests` over the fixture in
`openskyTests/M11ScriptedWorldChain.swift`. It needs no game data, and only its
last step needs a GPU.

The fixture is one synthetic exterior cell holding two references. The lever
carries a VMAD-attached `LeverScript` and one untagged `XLKR` link naming the
door; the door carries no script and is drawn. `LeverScript extends
ObjectReference`, and its compiled `OnActivate` body is the three instructions a
compiler emits for `ObjectReference linked = Self.GetLinkedRef()` followed by
`linked.Disable()`. That bytecode really executes on the interpreter — no probe
handler stands in for it.

The base script matters, and it is the reason the chain is honest. A method call
on a handle that has a live instance dispatches under that instance's root
script name, so `Self.GetLinkedRef()` inside `LeverScript` would look for a
native called `LeverScript.GetLinkedRef` and find nothing. The retail game
solves this by shipping `ObjectReference.pex`, whose functions are `native`
declarations with no body; `resolveMethod` walks the inheritance chain, finds
the declaration, and dispatches under the declaring script's name. The fixture
builds that same base object in code, which is why the natives resolve as
`ObjectReference.GetLinkedRef` and `ObjectReference.Disable`. Remove it and the
gate fails on `unimplementedNativeTotal`.

The chain the test drives, and what each step is asserted by:

1. **Use key.** The test enters at `CellStreamer.update(cameraPosition:
   interactionRay:activate:)`, the same call the render loop makes with the use
   key held. Everything above it is `GameViewController` key handling and an
   `MTKView` draw callback, which a headless test cannot drive; the raycast, the
   interaction target, the `InteractionEvent`, and the multicast fan-out are all
   real from that call downward.
2. **Activation recorded.** `ReferenceActivationState` on the lever with
   `activationCount == 1` and `lastActivator == .player`, and `isOpen` still
   false because an `activate` interaction is not a door.
3. **`OnActivate` dispatched.** The event drains through the tick loop and the
   handle that arrived as `akActionRef` resolves back to `ReferenceKey.player`.
   The tally shows three native calls, no fault, no unimplemented native and no
   native failure — evidence the bytecode ran to the end rather than degrading
   into declared defaults.
4. **World-state delta.** `ReferenceEnableState(isEnabled: false)` on the door,
   written by the script and not by the test. Both writes are attributed to the
   cell the streamer resolved: `dirtyCount(in:)` is 2 and
   `unattributedDirtyCount` is 0, so the rebuild fan-out stays narrowed to that
   one cell.
5. **Off the drawn set.** The delta goes back through a real `CellSceneBuilder`
   over a synthetic plugin whose object IDs match the session's, and the rebuilt
   cell reports `runtimeDisabledSkipCount == 1`, one drawn reference, one render
   instance at the lever's position, and no collision shape for the door. The
   door stays in `CellScene.references`, because disabled is not deleted. This
   step is gated on a Metal device; steps one through four assert
   unconditionally, so the gate still means something on a device-less runner.

Activation surviving a save is a separate assertion in
`PapyrusWorldActivationTests`: two activations encode and decode with
`activationCount` and `lastActivator` intact through
[the OpenSky save container](/formats/opensky-save.md), which is what makes a
lever that has been thrown stay thrown across a reload.

The discoverable `World > Scripts` sidebar surface and the M11 milestone
acceptance record are separate items and are not part of this gate.

## Deviations

The public references do not fully specify the Skyrim VM. OpenSky makes these
choices explicitly:

* Identifier, script, state, function, property and string equality is
  case-insensitive, while the first supplied string spelling is retained.
* Failed numeric and object casts fault the invocation. The wiki documents
  valid cast directions but not a bytecode-level failure value. An opaque
  handle with no attached script instance is accepted as an object type because
  this layer deliberately has no world type registry; attached Papyrus
  instances still validate their decoded inheritance chain.
* Float equality uses a four-ULP relative tolerance. The operator reference
  says the game accounts for a small epsilon but does not publish its value.
* Divide or modulo by zero is a typed fault. The operator reference calls the
  result undefined and says the game logs an error.
* Integer overflow wraps in 32-bit two's-complement arithmetic. Public
  references specify the width but not overflow behavior.
* Object and array string casts use stable OpenSky diagnostic text. The wiki
  promises readable object text but does not specify its exact format.
* Reaching the end of a function returns the declared type's default. The PEX
  format describes the instruction list but does not define fallthrough.
* A missing decoded method or static body routes to native dispatch. This is
  the only useful headless behavior for engine-defined base scripts, whose
  native implementations are not PEX bytecode.
* An unknown or failed native returns its declared default after logging and
  tallying the exact `(script, function)` pair and failure reason. Public
  references do not define a universal failure value, and aborting would hide
  later corpus behavior.
* `PlayAnimation`, `PlayAnimationAndWait`, and `PlayGamebryoAnimation` return
  true without changing a behavior graph until M14. This deliberate deviation
  is logged and tallied separately from honest native implementations.
* `GotoState` switches immediately but still does not enqueue `OnEndState` or
  `OnBeginState`. The wiki documents those events, and an event queue now
  exists, but it belongs to the main-actor `PapyrusWorldRuntime` while
  `GotoState` is an intrinsic inside the nonisolated interpreter, which has no
  path to it. Nothing in the engine delivers either event.
* Array find start-index normalization and the 100,000-element allocation cap
  are defensive OpenSky policy because the available opcode table does not
  document edge behavior or an allocation bound.

The world layer adds its own deliberate simplifications, each a stated
limitation rather than an oversight:

* `PapyrusValue.object` and `PapyrusValue.array` are not persistable. Their
  identity is runtime-allocated and means nothing in the world, so
  `instanceStates()` snapshots both as `.none` and a restore leaves the
  compiled default in their place.
* Persistent instances — those created from a reference entry flagged
  `isPersistent` — are never retired. They survive every `detach`, including
  world-space transitions, for the whole session.
* A reference that appears for the first time in a rebuilt cell gets its
  instance and its `OnInit` (it has never fired one), but no `OnCellAttach`
  and no `OnLoad`, because the cell did not re-attach.
* `firedOnInit` survives retirement. A non-persistent reference that leaves a
  cell and later re-enters it gets a fresh instance with compiled defaults but
  no second `OnInit`.
* A latent call whose instance was retired stays in the scheduler. When it
  wakes, the resume faults on the missing instance and is counted. This keeps
  retirement O(instances) instead of scanning every scheduler entry on every
  detach.
* A reference carrying several scripts resolves VMAD object properties to the
  instance with the lowest script name. One reference maps to one opaque
  handle, and picking the lowest name is deterministic where picking an
  arbitrary one would not be.

## Scope

This subsystem executes Skyrim PEX 3.x functions, dispatches the
world-independent native foundation, schedules real-time and game-time
suspensions deterministically, and runs inside the engine loop: one main-actor
runtime per session, script instances whose lifetime follows cell streaming, a
single FIFO event queue drained under a per-frame budget, and instance state
that survives a save and load.

It deliberately does not implement Fallout 4 structs, world-object native
functions, behavior graphs, or quest runtime behavior. The event queue carries
the three cell-lifecycle events the streamer can announce — `OnInit`,
`OnCellAttach` and `OnLoad` — and nothing else; every other Papyrus event
belongs to the subsystem that would raise it. Scheduling stays single-threaded
by design rather than by omission: the whole VM is confined to the main actor,
so there is no concurrent frame scheduling to reason about. Persistence covers
the primitive variable values, the active state and the `OnInit`-fired set,
not object or array identity.

Its opaque handles, initial-values table, native registry, suspension result,
scheduler and tally remain the seams headless consumers use without changing
the interpreter core, and `onCellAttached`, `onCellDetached`,
`onWorldUpdate` and `scriptProvider` are the seams the engine uses without the
VM ever depending on the engine.

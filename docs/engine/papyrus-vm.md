---
type: Engine Subsystem
title: Papyrus virtual machine
description: Bounded headless execution of Skyrim PEX functions with explicit
  frames, typed values, native registry, deterministic scheduling and tallies.
tags: [engine, papyrus, virtual-machine, bytecode]
timestamp: 2026-07-30T00:00:00Z
---

# Papyrus virtual machine

OpenSky executes the typed instructions produced by the
[PEX decoder](/formats/pex.md) in a headless Skyrim Papyrus virtual machine.
`PapyrusRuntime` owns the script library, attached instances, opaque object
handles, native registry, limits and tally. `PapyrusInterpreter` is created for
one invocation and owns its remaining instruction budget and explicit frame
stack. `PapyrusScheduler` advances suspended calls only from injected fixed
steps and game-clock samples.

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
* [Tests](#tests)
* [M11.1 acceptance](#m111-acceptance)
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
function name. `.empty` installs nothing. `.standard` installs 22 entries in
one place:

| family | functions | headless policy |
| --- | --- | --- |
| `Debug` | `Trace`, `MessageBox` | append to a bounded log and unified logging |
| `Utility` | `Wait`, `WaitGameTime`, `RandomInt`, `RandomFloat` | suspend on the injected clock or use a seeded generator |
| `Math` | `Abs`, `Floor`, `Ceiling`, `Sqrt`, `Pow`, `DegreesToRadians`, `RadiansToDegrees`, `Sin`, `Cos`, `Tan`, `Asin`, `Acos`, `Atan` | deterministic binary32 calculation |
| `ObjectReference` animation | `PlayAnimation`, `PlayAnimationAndWait`, `PlayGamebryoAnimation` | return true immediately, log and tally the deferred-animation deviation |

The corpus census found no string or form native that can be answered honestly
without world context. String basics are PEX opcodes, while the ranked form
functions require object identity, registration, or world state. They therefore
remain visible unknowns instead of receiving plausible-looking stubs.
Animation graph behavior belongs to M14. Until then the three animation calls
are the sole intentional success-without-effect family, and every occurrence is
measurable.

`PapyrusNativeContext` owns the seeded random source and bounded debug log.
Tests can inject a seed and assert exact sequences without reading a host clock
or global random generator.

## Deterministic scheduler

`PapyrusScheduler` accepts a fixed real-time step and sampled `GameClock`
values. `Utility.Wait` wakes after accumulated fixed steps;
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
* `GotoState` switches immediately but does not enqueue `OnEndState` or
  `OnBeginState`. The wiki documents those events, but this headless core has
  no event queue; the later scheduler owns that delivery boundary.
* Array find start-index normalization and the 100,000-element allocation cap
  are defensive OpenSky policy because the available opcode table does not
  document edge behavior or an allocation bound.

## Scope

This subsystem executes Skyrim PEX 3.x functions headlessly, dispatches the
world-independent native foundation, and schedules real-time and game-time
suspensions deterministically. It deliberately does not implement Fallout 4
structs, world-object native functions, behavior graphs, event queues,
concurrent frame scheduling, persistence, or quest runtime behavior. Its opaque
handles, initial-values table, native registry, suspension result, scheduler
and tally are the seams those consumers use without changing the interpreter
core.

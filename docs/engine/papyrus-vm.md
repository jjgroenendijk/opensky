---
type: Subsystem
title: Papyrus virtual machine
description: Bounded execution of Skyrim PEX functions - typed values, explicit frames, calls and
  suspension, the native registry, the deterministic scheduler, states, bounds, the tally, and the
  choices OpenSky makes where the references are silent.
tags: [engine, papyrus, virtual-machine, bytecode]
---

# Papyrus virtual machine

OpenSky runs the typed instructions the [PEX decoder](/formats/pex.md) produces. Three types make
the core, and none of them knows about the world:

- `PapyrusRuntime` owns the script library, instances, opaque object handles, the native registry,
  the limits, and the tally.
- `PapyrusInterpreter` is made for one call. It owns the remaining instruction budget and the frame
  stack.
- `PapyrusScheduler` moves suspended calls forward only from injected fixed steps and game clock
  samples.

The [Papyrus world runtime](/engine/papyrus-world.md) puts this core inside the engine loop. The
world natives are on the [activation](/engine/papyrus-activation.md),
[actor and faction](/engine/papyrus-actor-natives.md), [spell](/engine/papyrus-spell-natives.md),
[timer](/engine/papyrus-timers.md), and [quest](/engine/papyrus-quests.md) pages.

Language rules come from the Creation Kit wiki: the
[Papyrus category](https://ck.uesp.net/wiki/Category:Papyrus), the
[Literals Reference](https://ck.uesp.net/wiki/Literals_Reference), the
[Operator Reference](https://ck.uesp.net/wiki/Operator_Reference),
[Differences from Previous Scripting](https://ck.uesp.net/wiki/Differences_from_Previous_Scripting),
and [States (Papyrus)](https://ck.uesp.net/wiki/States_(Papyrus)). Instruction shapes and opcode
numbers come from
[UESP, Compiled Script File Format](https://en.uesp.net/wiki/Skyrim_Mod:Compiled_Script_File_Format).

## Values

A value is `None`, `Bool`, a signed 32-bit `Int`, an IEEE-754 binary32 `Float`, `String`, an opaque
object handle, or an array. The declared default is `False`, `0`, `0.0`, the empty string, or `None`
for an object or an array. The `Type[]` spelling is an array type.

Arrays keep their element type and are shared by reference, so a callee that changes an array
changes the caller's array too. Arrays of arrays and Fallout 4 structs do not exist here.

The truth rules are the documented ones. Zero, the empty string, `None`, and an empty array are
false. A non-zero number, a non-empty string, an object handle, and a non-empty array are true.
Number conversion accepts booleans and numeric strings, including the `0x` integer form.

## Instances

The runtime finds scripts by name, ignoring case. A new instance gets storage for its script and
every parent. It starts in the automatic state of the first script, from child to parent, that names
one. So a child with an empty automatic state starts in its parent's, as
[States (Papyrus)](https://ck.uesp.net/wiki/States_(Papyrus)) says. The shipped `Tripwire` relies on
this: it names no state, and `TrapTriggerBase` names `Inactive`.

A handle does not need an instance. `VMAD` may inject a world object whose scripts are not loaded.
A method call on that handle goes straight to native dispatch, and the script name is the declared
Papyrus type of the receiver.

Variables are stored under the script that declared them. So a child and a parent can each own a
private variable with the same name, and a function reads the scope of its own script first. When
its own script declares no such name, lookup walks up the parent chain. The install needs this: the
shipped `PressurePlate` writes `::Type_var`, which only its parent `TrapTriggerBase` declares. The
initial-values table replaces the first match from child to parent after checking the type. This is
the seam [VMAD binding](/formats/vmad.md) uses: it resolves direct object form IDs and uses the
automatic backing variable name stored in the PEX.

## Frames and execution

A frame holds the function, its script, the instance handle if any, parameters and locals, the
instruction pointer, and what to do on completion: return the result, assign it into the caller, or
drop a setter's result.

A branch offset is relative to the branch instruction itself, so `jmp 1` goes to the next
instruction. The install confirms it: compiled functions end in `jmp 1` as their last instruction,
which only makes sense as a jump to the end. A target equal to the instruction count ends the
function with its declared default. Any other out-of-range target is a fault.

All 36 PEX opcodes run: scalar (`nop`, assign, cast, return, not, negate), integer and float math,
comparisons, jumps, method, parent, and static calls, property get and set, string concatenation,
and the six array operations.

Integer add, subtract, multiply, and negate wrap in 32-bit two's complement, so hostile operands
cannot trap Swift. Division widens to 64 bits first, which also handles `Int32.min / -1`.

## Calls and suspension

A call pushes a frame onto the interpreter's own array. PEX never calls PEX through Swift
recursion.

Method lookup starts at the receiver's root script. `callparent` starts at the parent of the
function's own script. A static call targets the named script's empty-state function. A native flag,
or a call with no decoded body, goes to native dispatch.

A native returns a value, a failure with a reason, a suspension request, or a stated deviation. An
unknown `(script, function)` pair is logged and tallied, and the call returns its declared default.
A native failure does the same and keeps its reason. This keeps vanilla scripts moving without
inventing world state, and without treating an unknown native as a success.

A suspension keeps the request, the frames, where the result goes, and the remaining budget. It can
be resumed once. With no value given, the declared default is assigned. A second resume is a fault.

## Native registry

The registry keys functions by script and function name, ignoring case. The standard registry
installs these families:

| Family | Headless policy |
| --- | --- |
| `Debug`: `Trace`, `MessageBox` | A bounded log and unified logging |
| `Utility`: `Wait`, `WaitGameTime`, `RandomInt`, `RandomFloat` | Suspend on the injected clock, or use a seeded generator |
| `Math`: 13 functions | Deterministic binary32 math |
| `ObjectReference` animation: `PlayAnimation`, `PlayAnimationAndWait`, `PlayGamebryoAnimation` | Return true, and log and tally a deferred animation |
| World families: `ObjectReference`, `GlobalVariable`, `Game`, `Quest`, `Actor`, `Faction`, `Spell` | Fail with a reason, so the declared default is used |

Without a world, every world native fails with a reason. With one, they act through
[the world bridge](/engine/papyrus-activation.md#the-world-bridge). The world families are on the
pages linked at the top, and also in [crime](/engine/crime.md), [barter](/engine/barter.md),
[perks](/engine/perks.md), [skill advancement](/engine/skill-advancement.md), and
[character leveling](/engine/character-leveling.md).

`Game.GetPerkPoints` and `Game.ModPerkPoints` are SKSE functions: the Creation Kit wiki declares
both as SKSE additions to `Game`, and nothing else can read or write the perk point pool from a
script. OpenSky aims to support SKSE at the script level, never at the binary level.
`Game.SetPerkPoints` is absent on purpose rather than guessed. Both refuse when the session runs no
character leveling, because zero would read as a player who spent every point.

The corpus census found no string native that can be answered honestly without the world, and
string basics are opcodes, not natives. So they stay visible as unknowns instead of getting
plausible stubs. The animation calls are the only family that succeeds without an effect, and every
call is counted.

## Scheduler

`Utility.Wait` wakes after a whole number of fixed steps. A wake records the tick it started on and
compares whole ticks, `Double(tickCount - startTick) * fixedStepSeconds`. Adding 1/30 thirty times
drifts past 1.0, so the older form woke `Utility.Wait(1.0)` on step 31 instead of step 30.

`Utility.WaitGameTime` wakes after enough forward game hours. The first clock sample sets the
baseline. A backward jump adds zero. A forward jump adds at most 24 game hours per tick, so a clock
scrub cannot release an unbounded queue.

Calls due on the same tick resume in the order they were registered. A resumed call may suspend
again and takes its new place. The scheduler never reads the wall clock.

## Properties and arrays

An automatic property reads and writes its backing variable in its script's storage. A getter or
setter with a body runs as an ordinary frame. A missing accessor, variable, property, or receiver is
a fault.

A new array takes its element type from the destination and fills each slot with the default.
Negative and over-limit lengths are refused. Get and set check bounds, and set converts to the
element type. Find searches forward from `max(0, start)`. Reverse find treats a negative start as the
last element and clamps any other start to the last index. Both return -1 when nothing matches.

## States

Each instance has one active state, compared ignoring case. A function resolves in the wiki's
order:

1. the derived script in the active state;
2. each parent script in the active state;
3. the derived script in the empty state;
4. each parent script in the empty state.

`GotoState` and `GetState` are built into the VM when called on an instance. `GotoState` runs
`OnEndState` in the old state, switches, then runs `OnBeginState` in the new state, all before the
calling function goes on. Both hooks resolve like any other function, so a state without one uses the
empty state's. Trap scripts fire from these hooks: a pressure plate activates itself in
`active.onBeginState`.

## Bounds and faults

| Limit | Default | Bounds |
| --- | ---: | --- |
| Instruction budget | 1,000,000 | Loops and all nested calls |
| Call depth | 256 | The frame stack |
| Inheritance depth | 64 | Parent walks, and finds cycles |
| Array length | 100,000 | Allocation and linear search |
| Tally names | 256 | Distinct native names |
| Fault records | 64 | Kept fault detail |
| Native call records | 1,024 | The recorder tail |

A fault is a value, and the runtime stays usable after one.

The tally lives as long as the runtime. Its totals have no cap, and every name table filled from
script data is capped.

## Deviations

The public references do not fully describe the VM. These are OpenSky's choices:

- Names and string equality ignore case. The first spelling seen is kept.
- A malformed object can declare one variable name twice, or twice with different case. The
  references do not say what the game does then. The first declaration wins, because every lookup
  by name finds the first match. `PapyrusTally.duplicateVariableTotal` counts each skipped one.
- A method call on `None` returns its declared default and the function goes on, as the game logs
  "Cannot call ... on a None object" and continues. `PapyrusTally.noneReceiverTotal` counts them.
- A failed cast faults the call. The wiki gives valid cast directions but no failure value. A handle
  with no instance is accepted as any object type, because this layer has no world type registry.
  Before it faults, a cast tries another instance on the same form whose script has the target type,
  because the game keeps all scripts of one form in one object.
- Float equality allows four ULPs of relative difference. The wiki says the game uses a small
  epsilon but does not give it.
- Division or modulo by zero is a fault. The wiki calls the result undefined and says the game logs
  an error.
- Integer overflow wraps. The references give the width but not the overflow rule.
- Running off the end of a function returns the declared default.
- An unknown or failed native returns its declared default after logging, because aborting would
  hide what the script does next.
- `GetState` inside `OnEndState` already returns the new state. Both hooks run as frames that
  `GotoState` pushes, and the switch happens before either frame starts.
- Array find start clamping and the 100,000 element cap are defensive policy. The opcode table does
  not give either.

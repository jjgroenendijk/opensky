---
type: File Format
title: Conditions (CTDA, CITC, CIS1, CIS2)
description: The shared 32-byte CTDA condition payload, its sibling count and string
  subrecords, the skip-don't-throw decode policy, and the function registry and
  evaluator that answer a condition list at runtime.
tags: [format, plugin, conditions]
timestamp: 2026-08-02T00:00:00Z
---

# Conditions (CTDA, CITC, CIS1, CIS2)

A condition is the shared "is this true right now?" test that Skyrim attaches to
dozens of record types. Quests, dialogue, packages, music, perks, and magic
effects all gate behavior through the same `CTDA` subrecord, so one decoder
serves all of them.

This page covers both halves of the subject. The first half is the on-disk
layout: what the 32 bytes mean and how OpenSky decodes them. The second half is
evaluation — resolving the function index through a registry, applying the
comparison and OR-grouping semantics, and binding a run-on target — which
issue #251 added on top of the decoder and which this page documents from
[Function registry and evaluation](#function-registry-and-evaluation) onward.

## Contents

* [CTDA payload](#ctda-payload)
* [Comparison operator and flags](#comparison-operator-and-flags)
* [Run-on type](#run-on-type)
* [Sibling subrecords](#sibling-subrecords)
* [Decode policy](#decode-policy)
* [Function registry and evaluation](#function-registry-and-evaluation)
* [Observed in Skyrim.esm](#observed-in-skyrimesm)
* [Coverage sweep](#coverage-sweep)
* [References](#references)
* [See also](#see-also)

Decoder: `Condition` and `ConditionList` in
`opensky/Formats/ESM/Records/Condition.swift`. `MusicTrack` is the first
consumer; other record types adopt the same accumulator as they land.

Evaluator: `ConditionEvaluator`, `ConditionFunctionRegistry`,
`ConditionFunctions`, `ConditionFunctionsTime` and `ConditionTally`, all in
`opensky/World/`.

## CTDA payload

Every `CTDA` payload is exactly 32 bytes, little-endian.

| offset | size | on-disk type | field | notes |
| --- | --- | --- | --- | --- |
| 0 | 1 | uint8 | operator and flags | top 3 bits comparison operator, low 5 bits flags |
| 1 | 3 | bytes | unused | may hold nonzero garbage, never validated |
| 4 | 4 | float32 or FormID | comparison value | a `GLOB` FormID when the use-global flag is set, otherwise a float |
| 8 | 2 | uint16 | function index | stored already offset by -4096 against Creation Kit numbering |
| 10 | 2 | bytes | padding | may hold nonzero garbage, never validated |
| 12 | 4 | raw word | parameter #1 | typed per function; kept raw |
| 16 | 4 | raw word | parameter #2 | typed per function; kept raw |
| 20 | 4 | uint32 | run-on type | see below |
| 24 | 4 | FormID | reference | meaningful only when the run-on type is Reference |
| 28 | 4 | int32 | parameter #3 | -1 when unused |

The function index decides how the two parameter words and the comparison value
should be read, and the decoder deliberately does not consult the function
table: `Condition` stores both parameters verbatim as a `Parameter` wrapper
exposing `asFloat`, `asFormID`, and `asInt32`. The evaluator reinterprets a word
once it has matched the index to a `ConditionFunction`, so decode stays total
and a plugin naming a function OpenSky has never heard of still round-trips.

The -4096 offset is a numbering difference, not an encoding one: the Creation
Kit documents `GetWantBlocking` as function 4096, and the same function is
stored as 0 on disk. OpenSky keeps the raw on-disk value and does not adjust it.

The field at offset 28 is named "Parameter #3" by xEdit and described by UESP as
the index of the package data or quest alias to run on. The two readings cover
the same bytes; OpenSky stores the signed value without interpreting it.

## Comparison operator and flags

The operator occupies the top 3 bits of byte 0, so the enumerated value is the
byte shifted right by five.

| value | operator |
| --- | --- |
| 0 | equal to |
| 1 | not equal to |
| 2 | greater than |
| 3 | greater than or equal to |
| 4 | less than |
| 5 | less than or equal to |
| 6, 7 | undefined |

The low 5 bits are flags.

| bit | meaning |
| --- | --- |
| `0x01` | OR with the next condition instead of AND |
| `0x02` | use aliases: reference-typed parameters are quest alias indices |
| `0x04` | use global: the comparison value is a `GLOB` FormID |
| `0x08` | use pack data: reference-typed parameters are package data indices |
| `0x10` | swap subject and target |

Flags `0x02` and `0x08` are mutually exclusive. UESP marks the swap flag with a
question mark; xEdit names it without qualification.

## Run-on type

| value | run-on |
| --- | --- |
| 0 | subject |
| 1 | target |
| 2 | reference |
| 3 | combat target |
| 4 | linked reference |
| 5 | quest alias |
| 6 | package data |
| 7 | event data |

## Sibling subrecords

`CITC` is a uint32 stating how many `CTDA` fields follow it. It is optional on
`FACT` and `MUST`, and required on `SMBN`, `SMQN`, `SMEN`, and inside each
`PACK` procedure-tree branch — required even when the count is zero, so `CITC`
presence correlates poorly with `CTDA` presence.

`CIS1` and `CIS2` are zero-terminated strings that override parameter #1 and
parameter #2 of the immediately preceding `CTDA`. When one is present the
corresponding raw parameter word in the `CTDA` is arbitrary and carries no
meaning.

## Decode policy

Plugin data from mods is not trustworthy, so the decoder degrades instead of
throwing:

* A `CTDA` payload that is not exactly 32 bytes is skipped. `Condition.init?`
  returns nil rather than throwing, and the surrounding fields decode normally.
* Operator values 6 and 7, and run-on values above 7, round-trip through an
  `unknown` case that keeps the raw byte or word.
* A `CIS1` or `CIS2` with no preceding condition — because the `CTDA` it
  belonged to was skipped — is dropped.
* A wrong-width `CITC` is consumed and ignored.
* The reference word at offset 24 is never validated, in any run-on type.

`ConditionList` is the accumulator each record decoder forwards its unmatched
fields to. Its `decode(field:)` returns false for anything that is not part of a
condition run, so an owning record keeps matching its own fields afterwards and
no record type reimplements this logic.

The declared `CITC` count is recorded as `declaredCount` but never trusted over
the `CTDA` fields actually decoded, for the reason in the next section.

## Function registry and evaluation

Issue #251 (milestone M10.2, item 10.2.4) added the layer that answers "is this
condition list true right now?". It lives under `opensky/World/` rather than
beside the decoder under `opensky/Formats/`, because answering a condition needs
runtime state a format parser must never reach for: the global-value seam, the
game clock, and the per-cell runtime reference index
([runtime reference identity and world state](/engine/runtime-state.md)).

### Comparing one condition

A single condition is the test `functionReturn <operator> comparisonValue`. The
function's return value is the left-hand side, the decoded comparison value is
the right-hand side, and both are `Float`.

Equality is exact. Neither UESP nor the Creation Kit wiki documents a tolerance
for the equal and not-equal operators, so `ConditionEvaluator.compare(_:_:_:)`
compares floats directly rather than through an invented epsilon. That is
OpenSky's recorded choice, made this way because a fudge factor nobody
documented would be an undocumented behavior difference hiding inside an
otherwise faithful comparison; an exact compare is at least the same wrong or
right answer every time. The two undefined operator encodings (6 and 7) return
nil from `compare` and become a reason-tagged false.

When the use-global flag (`0x04`) is set, the right-hand side is a `GLOB`
FormID rather than a literal, and it resolves through
`GlobalResolution.comparisonValue(_:)`. A `nil` from that seam means the
condition names a global nothing in the load order defines. That is reported as
`ConditionFailure.unresolvedGlobal` and is deliberately *not* treated as a
comparison against zero, because zero is a value a mod may legitimately compare
against and silently substituting it would turn a coverage gap into a wrong
answer.

### OR grouping

The Creation Kit wiki's Conditions documentation defines the OR flag as
replacing the operator *between* condition N and condition N+1 with OR. Two
consequences follow, and OpenSky implements both:

* Consecutive OR-joined conditions form one disjunction block, and blocks
  combine with AND, so OR binds tighter than AND. The wiki's own example,
  `A AND B OR C AND D`, therefore evaluates as `(A AND (B OR C) AND D)` rather
  than as a flat left-to-right fold.
* An OR flag on the *final* condition has no following operator to replace. The
  documented rule says nothing about that case, so OpenSky takes the
  conservative reading and ends the block with the list instead of inventing a
  wrap-around or discarding the condition.

An empty condition list is true, which is what an unconditioned record means.

`ConditionEvaluator` never short-circuits: every condition in a list is
evaluated even after the result is decided. That costs a little work and buys
the thing the tally exists for — a coverage report over the whole list rather
than over whatever prefix happened to settle it.

### Run-on resolution

The run-on word selects the object the function runs against. Only three of the
eight types have a live resolution today, and the two failure modes are kept
apart on purpose:

* Subject, target and reference resolve through `ConditionContext`. Subject and
  target come from the `subject` and `target` keys the caller bound; reference
  looks the raw FormID at offset 24 up in the `RuntimeReferenceIndex`. The
  `swapSubjectAndTarget` flag (`0x10`) is honoured here, which is the only place
  it can matter.
* Combat target, linked reference, quest alias, package data, event data and any
  unknown value fail up front as `ConditionFailure.unsupportedRunOn`, with their
  own tally bucket. This is a missing subsystem, not a missing binding.
* A supported run-on that names a reference the context cannot produce — no
  subject bound, or a key the index does not hold — is
  `ConditionFailure.unresolvedReference`, a different bucket, because the fix is
  a caller supplying a better context rather than OpenSky implementing more
  engine.

Resolution is lazy. A function asks for a reference only if it needs one, so
`GetCurrentTime` still answers in a context with no subject bound at all, and a
run-on type OpenSky cannot resolve does not poison a condition that never
touches it.

### The evaluation context

`ConditionContext` is a value type composed of `globals: GlobalResolution`,
`quests: QuestResolution`, an optional `clock: GameClock`, a
`references: RuntimeReferenceIndex`, the `subject` and `target` `ReferenceKey`s,
and `random: ConditionRandom`. Building
one is cheap, so a caller evaluating off the main actor builds its own from a
snapshot instead of reaching into the live stores.

`ConditionRandom` is a SplitMix64 value type with `init(seed:)` and
`percent()`. It is a value type rather than a closure or a protocol
specifically so it stays `Sendable` and seed-deterministic without a lock: the
engine seeds it once per session and a test seeds it per test, and the same seed
replays the same sequence of draws.

### Implemented functions

Nine functions are registered, chosen because the engine can answer them
honestly from state it already owns. The stored index is the raw on-disk value;
the Creation Kit spells each one 4096 higher
(`ConditionFunctionRegistry.creationKitOffset`).

| stored | Creation Kit | name | parameters | returns |
| --- | --- | --- | --- | --- |
| 18 | 4114 | `GetCurrentTime` | none | current game time as a decimal hour, 0 to 24 — 4:30 am is 4.5 |
| 56 | 4152 | `GetQuestRunning` | #1 `QUST` FormID | 1 when the quest is running, 0 otherwise |
| 58 | 4154 | `GetStage` | #1 `QUST` FormID | the highest stage the quest has reached, 0 when it has reached none |
| 59 | 4155 | `GetStageDone` | #1 `QUST` FormID, #2 stage index | 1 when that stage was explicitly visited, 0 otherwise |
| 72 | 4168 | `GetIsID` | #1 base-object FormID | 1 when the run-on reference's base form matches the parameter, 0 otherwise |
| 74 | 4170 | `GetGlobalValue` | #1 `GLOB` FormID | the named global's current value |
| 77 | 4173 | `GetRandomPercent` | none | an integer 0 to 99 inclusive |
| 170 | 4266 | `GetDayOfWeek` | none | 0 for Sundas through 6 for Loredas |
| 543 | 4639 | `GetQuestCompleted` | #1 `QUST` FormID | 1 when the quest is flagged completed, 0 otherwise |

Several of these carry a recorded decision.

`GetCurrentTime` reads the game clock when the context has one and falls back to
the `GameHour` global when it does not. That fallback is an OpenSky choice, not
a spec rule: it exists so a condition list evaluated against a plugin-only
context — an inspector, a test, a tool with no world running — gets the
plugin's authored time of day rather than a reason-tagged false. With a clock
present the clock always wins, which keeps the authority rule on
[the game clock page](/engine/game-clock.md) intact.

`GetDayOfWeek` counts weekdays from the vanilla start date rather than from the
clock epoch. UESP's `Skyrim:Calendar` states that a new game begins on the 17th
of Last Seed as Sundas, and the Creation Kit wiki's `GetDayOfWeek` page maps
return value 0 to Sundas, so those two documented facts pin the anchor together.
An earlier attempt anchored the count at the clock epoch (4E 0, 1st of Morning
Star, assumed to be Sundas) and placed the vanilla start on Tirdas — wrong by
two days, and wrong in a way no test that only checked internal consistency
would have caught. `ConditionFunctions.dayOfWeek(of:)` now counts
`GameClock.daysPassed` against a documented `vanillaStartWeekday = 0`. The
Tamriel year has 365 days and no leap day, so weekdays advance one per day and
drift against the calendar year exactly as the lore says they do. UESP notes one
exception OpenSky does not model: loading an existing save before starting a new
game carries that save's weekday over.

The four quest functions (issue #182) read the `quests` seam and nothing else,
so they answer without a world, a clock or a reference. Their state semantics —
"highest reached" for `GetStage`, "explicitly visited" for `GetStageDone` — are
documented on [runtime state](/engine/runtime-state.md) with their Creation Kit
citations. Two edge choices are OpenSky's:

* `GetStageDone` with a stage index outside the uint16 range answers 0 rather
  than failing. Stage indices are uint16 on disk, so no such stage can exist,
  and "not done" is a real answer instead of a coverage gap.
* `GetQuestCompleted` implements the *fixed* behaviour. The Creation Kit wiki
  records that the original engine returned 0 unconditionally until patch
  1.9.32, and suggests `GetStageDone` on the last stage as the workaround. A
  plugin authored around the bug still evaluates correctly here; one that
  relied on the broken return does not. Reproducing a documented, patched bug
  would make every correct condition wrong.

`ConditionFunction` carries `index`, `name`, `parameter1` and `parameter2` as
`ConditionParameterType` (`.unused`, `.formID`, `.integer`, `.float`), and
`creationKitIndex`. The registry (`ConditionFunctionRegistry.standard`, with
`.empty` for tests that want every index unknown) exposes `register(_:)`,
`subscript(UInt16)`, `indices`, `name(for:)` and `sortedFunctions()`. Its shape
deliberately mirrors `AS2Natives` in the ActionScript runtime — one `install`
entry point, families split into satellite files, no giant switch — so adding
functions is registration rather than surgery.

### Failure model and the tally

Nothing in the evaluator throws. A condition it cannot answer evaluates to
false and carries a machine-readable `ConditionFailure` saying why:
`.unknownFunction`, `.unresolvedGlobal`, `.unresolvedQuest`,
`.unsupportedRunOn`, `.unresolvedReference`, `.unknownOperator`,
`.unresolvedParameter`, or `.unavailableClock`. A QUST parameter naming no quest
is `.unresolvedQuest` rather than a stopped quest at stage zero: "this quest does
not exist" and "this quest has not started" are different answers, and only one
of them is real. `ConditionOutcome` pairs the `isTrue` a caller needs with
the `failures` that explain it and an `isConclusive` flag that is true only when
the answer came from real evaluation rather than from a fallback. A caller that
wants a Bool never has to write an error path; a caller that cares about honesty
checks `isConclusive`.

Every failure also lands in `ConditionTally`, which mirrors `AS2Tally` from the
[ActionScript 2 runtime](/engine/as2-runtime.md) and is a first-class result
rather than a debug aid. It answers "which condition functions does OpenSky
still owe Skyrim, and how much do they matter?", which is the question that
ranks the next milestone's work. Its buckets are `unknownFunctions` with
`unknownFunctionTotal` and `unnamedUnknownFunctions` beside it,
`unresolvedGlobals`, `unresolvedQuests`, `unsupportedRunOns` keyed by run-on name,
`unresolvedReferences`, `unknownOperators`, `unresolvedParameters` and
`unavailableClock`, plus the volume counters `conditionsEvaluated` and
`listsEvaluated`, the derived `failureTotal` and `isClean`, and ranked
accessors for reporting. Each name table is capped at `nameLimit` (64 by
default) so a pathological plugin cannot grow the tally without bound, while
the totals keep counting past the cap — a truncated table still reports how much
it stopped naming.

Because an unknown index is a counted false rather than an error, adding
functions later is purely additive. M12 registers its inventory checks, M16 its
detection checks and M17 its dialogue checks alongside the subsystems that make
those answerable, and nothing already written changes.

There is no inspector surface for evaluation yet. Evaluate-and-show plus the
tally readout land with the M10.2 acceptance gate, issue #166, which owns the
panel changes for the whole sub-milestone. That panel's context carries an empty
quest seam, because nothing in the app session builds a `QuestStore` yet; quest
conditions evaluated there are therefore honestly reported as
`unresolved quest` until the journal UI (#184) wires one in.

### Evaluator tests

* `ConditionEvaluatorTests` — every comparison operator including the two
  undefined encodings, literal and global right-hand sides, the unresolved-global
  case, OR grouping against the documented example and the trailing-OR case, the
  empty list, run-on selection with and without the swap flag, and the tally
  buckets each failure lands in.
* `ConditionFunctionTests` — the identity and global functions against synthetic
  contexts, the registry's index and naming surface, and the seeded determinism
  of `ConditionRandom` including its 0-99 bound.
* `QuestConditionFunctionTests` — the four quest functions against synthetic
  quest state, both from a runtime override and from a plugin baseline, plus the
  unresolvable-quest failure path and an empty quest seam.
* `ConditionTimeFunctionTests` — `GetCurrentTime` from a clock and from the
  `GameHour` fallback, and `GetDayOfWeek` against the documented vanilla start
  weekday across a year boundary.

Every fixture is built in code (`ConditionEvaluatorFixture`); no game bytes are
committed. The real-data sweep in `ConditionRealDataTests` is the separate,
env-gated check described in the next two sections.

## Observed in Skyrim.esm

`ConditionRealDataTests` sweeps every record in the shipped `Skyrim.esm` and
decodes every `CTDA` it finds. Observed 2026-07-28 against the retail Special
Edition install: 83,759 conditions over 32,501 records, with zero skipped
payloads and zero errors. No unknown operator and no unknown run-on value
appears in vanilla data, so both `unknown` cases exist purely for mod tolerance.

Carriers, by condition count: `INFO` 24,328, `PACK` 2,442, `IDLE` 1,757, `QUST`
1,307, `COBJ` 526, `SCEN` 498, `SMQN` 379, `PERK` 338, `MGEF` 318, `SNDR` 198,
`SPEL` 106, `SMBN` 78. Of those conditions, 1,681 use a global comparison value,
11,666 carry the OR flag, and 4,774 carry a `CIS1` or `CIS2` override.

Raw function indices span 0 to 726 across 244 distinct values. Index 0 being
present confirms the on-disk -4096 offset, since Creation Kit numbering starts
at 4096.

Two points the open references leave ambiguous were resolved by this sweep:

`CITC` counts one condition run, not every condition in the record. 142 records
disagree between their declared count and the number of `CTDA` fields present,
and every one of them is a `PACK`: the `CITC` covers the package's own
conditions while the remaining `CTDA` fields belong to nested package-data
blocks. The decoder therefore keeps the declared count as information and
always reports the conditions it actually decoded.

The reference word at offset 24 is clean in vanilla data. No condition whose
run-on type is anything other than Reference carries a nonzero reference,
so xEdit marking the field ignored is a tolerance allowance rather than
something the shipped plugin exercises. OpenSky still never validates it,
because mods may.

## Coverage sweep

`ConditionRealDataTests` runs the registry over every condition the decode sweep
finds, counting what the evaluator could name and what it could not. Observed
2026-08-02 against the retail Special Edition install, after the four quest
functions landed: **35,460 of 83,759 conditions (42.34%) name a function the
registry implements**. Those nine functions are 9 of the 244 distinct raw
indices present in the file, whose range is 0 to 726.

| stored | Creation Kit | function | conditions |
| --- | --- | --- | --- |
| 72 | 4168 | `GetIsID` | 19,169 |
| 58 | 4154 | `GetStage` | 8,029 |
| 59 | 4155 | `GetStageDone` | 4,175 |
| 74 | 4170 | `GetGlobalValue` | 1,579 |
| 77 | 4173 | `GetRandomPercent` | 1,203 |
| 18 | 4114 | `GetCurrentTime` | 518 |
| 543 | 4639 | `GetQuestCompleted` | 470 |
| 56 | 4152 | `GetQuestRunning` | 316 |
| 170 | 4266 | `GetDayOfWeek` | 1 |

Nine functions covering better than two fifths of the file is the shape a long
tail has: `GetIsID` alone is 22.9% of every condition in the game, and the two
quest-stage functions are another 14.6% between them. The earlier sweep, run on
2026-07-29 with only the first five functions registered, measured 22,470
conditions (26.83%) — quest state was the single largest thing the evaluator
could not answer, which is why #251 named it the top of the demand list.

The remaining 235 indices carry 48,299 conditions. The ten heaviest, by stored
index and the Creation Kit number 4096 above it:

| stored | Creation Kit | conditions |
| --- | --- | --- |
| 71 | 4167 | 6,904 |
| 426 | 4522 | 6,584 |
| 566 | 4662 | 5,504 |
| 629 | 4725 | 4,584 |
| 560 | 4656 | 1,943 |
| 359 | 4455 | 1,058 |
| 46 | 4142 | 1,028 |
| 448 | 4544 | 1,022 |
| 67 | 4163 | 919 |
| 550 | 4646 | 799 |

These are indices, not names. The sweep measured what the plugin stores, and it
stores numbers; naming them from memory is exactly the kind of confident guess
this project does not make. Each becomes a name when a function is implemented
against a cited source. The full top-20 table, together with every other tally
bucket, is written to `logs/condition-sweep.log`, which is gitignored because it
is derived from the user's own installed plugin.

The sweep also settled the one index the open sources disagreed about.
`GetRandomPercent` is 77 in xEdit's TES5 condition-function table, while the
older gib.me list implies 76. Vanilla data is decisive: stored index 76 does not
appear in `Skyrim.esm` at all, while stored index 77 carries 1,203 conditions
whose parameter words are zero in every single case, whose comparison values
span 0.0 to 100.0 across 36 distinct values, and 1,152 of which compare against
a number inside 0 to 100 (51 of the rest compare against a global). A
no-parameter function compared against a percentage is exactly that signature,
so the registry uses 77.

## References

* UESP, "Skyrim Mod:Mod File Format/CTDA Field" —
  <https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/CTDA_Field>. Note the
  page name is `CTDA_Field`; the bare `CTDA` page is empty.
* xEdit (TES5Edit), `wbDefinitionsTES5.pas`, `wbCTDA` and the surrounding
  deciders — <https://github.com/TES5Edit/TES5Edit>.
* Creation Kit wiki, Conditions category — <https://ck.uesp.net/wiki/Category:Conditions>.
  The OR-flag grouping rule and its `A AND B OR C AND D` example come from here.
* Creation Kit wiki, the individual function pages under
  <https://ck.uesp.net/wiki/>: `GetCurrentTime`, `GetIsID`, `GetGlobalValue`,
  `GetRandomPercent` and `GetDayOfWeek`, for each function's return value,
  parameter typing and value range.
* UESP, "Skyrim:Calendar" — <https://en.uesp.net/wiki/Skyrim:Calendar>. The
  vanilla start date and its weekday, which anchor `GetDayOfWeek`.

## See also

* [Music records (MUSC, MUST)](/formats/music.md) — the first record type to
  decode conditions through this model.
* [ESM plugin format](/formats/esm.md) — the record and field framing conditions
  arrive in.
* [FormID](/formats/formid.md) — how the comparison-value and reference FormIDs
  resolve against the load order.
* [Runtime reference identity and world state](/engine/runtime-state.md) — the
  `GlobalResolution` seam the evaluator reads comparison values through, and the
  `RuntimeReferenceIndex` its run-on resolution looks references up in.
* [Game clock and calendar](/engine/game-clock.md) — the clock `GetCurrentTime`
  and `GetDayOfWeek` read, and the authority rule between it and the time
  globals.
* [ActionScript 2 runtime](/engine/as2-runtime.md) — `AS2Tally` and `AS2Natives`,
  the coverage-tally and registry patterns `ConditionTally` and
  `ConditionFunctionRegistry` follow.

---
type: Subsystem
title: Behavior state machines
description: How a behavior graph state machine enters a state, which transition wins, the
  transition flag map checked against the install, the condition grammar, and crossfades.
tags: [engine, animation, havok, hkx, behavior]
---

# Behavior state machines

A `hkbStateMachine` moves a character between states, such as standing, walking, and jumping. The
rest of the runtime is on the [behavior graph runtime](/engine/behavior-runtime.md) page.

## States

A machine holds one current state and at most one transition in progress. The machine's state
outlives deactivation, because `m_startStateMode` 2 re-enters whatever was current when the machine
stopped. 121 of the 1,963 machines in the vanilla player graph use that mode.

Entering picks the start state. The first match wins:

1. The state ID a parent's transition named with `FLAG_TO_NESTED_STATE_ID_IS_VALID`. This is how a
   parent machine sends the machine inside its destination state to a chosen state, instead of that
   machine's own start state.
2. For `m_startStateMode` 2, the remembered ID.
3. For `m_startStateMode` 1, the value of the variable at `m_syncVariableIndex`.
4. `m_startStateId`, with any binding on `startStateId` applied. The vanilla data uses that binding
   a lot.

Entering raises the state's `m_enterNotifyEvents` and the machine's
`m_eventToSendWhenStateOrTransitionChanges`. Leaving raises `m_exitNotifyEvents`. So does
deactivation: a machine that is no longer reached leaves its state.

A state whose generator is another `hkbStateMachine` runs it the same way. The runtime publishes
every machine the last update reached, in walk order with the outermost first: the machine name,
the state name, and the crossfade weight. The locomotion panel shows this path.

## Transitions

Candidates come from two places: the current state's `hkbStateMachineTransitionInfoArray`, then the
machine's `m_wildcardTransitions`, which apply from any state. A candidate fires when all of these
hold:

- `FLAG_DISABLED` is clear.
- Its `m_eventId` is in the active event set. So an event raised during an update moves the machine
  on the next update, like every other event.
- Its `m_toStateId` names an enabled state. The state must differ from the current one, unless the
  transition has `FLAG_ALLOW_SELF_TRANSITION_BY_TRANSITION_INFO`.
- If `FLAG_USE_TRIGGER_INTERVAL` or `FLAG_USE_INITIATE_INTERVAL` is set, that interval is open. An
  interval opens when its `m_enterEventId` is raised and closes on its `m_exitEventId`. Every time
  bound in the vanilla player graph is zero, so a non-zero bound is counted.
- Its condition holds (see below).

Of the candidates that can fire, the highest `m_priority` wins. At equal priority, the state's own
transition beats a wildcard. After that, array order wins. No source consulted documents Havok's
own tie-break, so this order is a choice. A total order keeps two instances stepping the same way.

The state changes when the transition starts: `currentStateId` becomes the destination, the exit
and enter events fire, and the effect only fades out the old pose. That is why
`FLAG_DELAY_STATE_CHANGE` exists as a separate flag. It is set on 14 of the 3,769 transitions in
the vanilla player graph, and it is counted, not used.

An event that arrives during a crossfade starts a new transition from the machine's current state.
The older blend is dropped, not nested, and each drop counts one
`stateMachineTransitionInterrupted`. Havok allows effects to stack, so here an interruption can
jump by the part of the old blend still running. A transition with
`FLAG_UNINTERRUPTIBLE_WHILE_PLAYING` or `FLAG_UNINTERRUPTIBLE_WHILE_BLENDING` refuses the new
candidate.

The four machine-level event IDs are checked only when no transition fired:

- `m_returnToPreviousStateEventId` goes back one state.
- `m_transitionToNextHigherStateEventId` and `m_transitionToNextLowerStateEventId` step through the
  sorted state IDs, and respect `m_wrapAroundStateId`.
- `m_randomTransitionEventId` picks the enabled state with the highest `m_probability`, with ties
  going to the lowest ID, and counts `stateMachineRandomTransitionFixed`. A graph that picks
  animation from an unseeded random source cannot be stepped twice with the same result.

Of 530 machines in the two `mt_behavior` files, four name a random transition event and none name
the other three.

## The flag map

The `hkbStateMachineTransitionInfo::TransitionFlags` names come from the same open-source lineage
as the byte layouts ([Havok behavior scope](/decisions/havok-behavior-scope.md)). Every bit the
runtime uses was then checked against the install:

| Bit | Name | Use in the vanilla player graph |
| --- | --- | --- |
| `0x1` | `USE_TRIGGER_INTERVAL` | 24 transitions |
| `0x2` | `USE_INITIATE_INTERVAL` | 144, each with an event pair |
| `0x4` | `UNINTERRUPTIBLE_WHILE_PLAYING` | 70 |
| `0x8` | `UNINTERRUPTIBLE_WHILE_BLENDING` | Never set |
| `0x10` | `DELAY_STATE_CHANGE` | 14 |
| `0x20` | `DISABLED` | 2 |
| `0x100` | `DISABLE_CONDITION` | 3,340, exactly the transitions with a null `m_condition` |
| `0x200` | `ALLOW_SELF_TRANSITION` | 75 |
| `0x400` | `IS_GLOBAL_WILDCARD` | 729, only in wildcard arrays |
| `0x800` | `IS_LOCAL_WILDCARD` | 1,167, only in wildcard arrays |
| `0x1000` | `FROM_NESTED_STATE_ID_IS_VALID` | 24. Counted, not used |
| `0x2000` | `TO_NESTED_STATE_ID_IS_VALID` | 642, only where the ID names a nested state |

`0x40`, `0x80`, and `0x4000` are never set. The `0x100` match is the strongest evidence here. A bit
that is set on every transition with no condition object, and clear on every transition with one,
can only mean "do not evaluate the condition".

## Transition conditions

`hkbExpressionCondition` and `hkbStringCondition` hold their test as text. Havok compiles it at load
into a `SERIALIZE_IGNORED` member, so the file holds only the source text. The grammar was recovered
from the vanilla files. 429 of the 3,769 transitions name a condition, and every one fits:

```text
or         := and ( "||" and )*
and        := comparison ( "&&" comparison )*
comparison := unary ( ( "==" | "!=" | ">=" | "<=" | ">" | "<" ) unary )?
unary      := "!" unary | primary
primary    := number | variable | "(" or ")"
```

Examples from the data:

- `IsFirstPerson == 0`
- `(IsNPC == 0) && (iLeftHandType != 7) && (iLeftHandType != 12)`
- `(iWantBlock == 0) || (iLeftHandType == 7)`
- `!bIsSynced && !bIsRiding`
- `Speed >= fMinSpeed`, a variable against a variable
- `(staggerDirection < .25) || (staggerDirection > .75)`, a literal with a leading dot

There are no string literals, no arithmetic, no function calls, and no assignment. Every value is a
float, and a bare variable is true when it is not zero. That is how `!bBlendOutSlow` reads.

Text that does not parse, or names a variable the graph does not declare, blocks the transition and
is counted (`transitionConditionUnparsed`, `transitionConditionUnresolved`). Blocking fails where it
can be seen. An animation that does not start looks like a bug. An animation that starts wrongly
looks like engine behavior.

## Crossfades

`hkbBlendingTransitionEffect` fades the old state's pose into the new one over `m_duration`, shaped
by `hkbBlendCurveUtils::BlendCurve`. The vanilla player graph uses two curves, 389 smooth and 8
linear, so only those two have a formula: smooth is `3t^2 - 2t^3`, and linear is `t`. Any other
curve falls back to smooth and is counted. A formula for a curve no file uses would be invented.

A null `m_transition` and a zero `m_duration` both mean a cut. 198 of the 397 blending effects in
the vanilla player graph have a zero duration. The clock runs after selection, so a transition that
starts in an update already shows one step of its crossfade. One that reaches its duration is
dropped, not drawn at a weight of exactly 1.

Of the effect's `FlagBits`, only the sync bit is used
([clip synchronization](/engine/behavior-clips.md)).

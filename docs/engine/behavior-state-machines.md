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

A machine holds one current state and a transition in progress, which can hold the
transitions it interrupted.

Entering picks the start state. The first match wins:

1. The state ID a parent's transition named with `FLAG_TO_NESTED_STATE_ID_IS_VALID`. This is how a
   parent machine sends the machine inside its destination state to a chosen state, instead of that
   machine's own start state.
2. For `m_startStateMode` 2, a random enabled state, drawn by `m_probability`. 121 of the 1,963
   machines in the vanilla player graph use that mode.
3. For `m_startStateMode` 1, the value of the variable at `m_syncVariableIndex`.
4. `m_startStateId`, with any binding on `startStateId` applied. The vanilla data uses that binding
   a lot. Mode 3, the chooser, also uses it.

A start state the machine does not hold, or one that is disabled, falls back to the first enabled
state in array order. Only a machine with no enabled state is counted.

Entering raises the state's `m_enterNotifyEvents` and the machine's
`m_eventToSendWhenStateOrTransitionChanges`. Leaving raises `m_exitNotifyEvents`. So does
deactivation: a machine that is no longer reached leaves its state.

A state whose generator is another `hkbStateMachine` runs it the same way. The runtime publishes
every machine the last update reached, in walk order with the outermost first: the machine name,
the state name, and the crossfade weight.

## What a machine publishes

A machine writes three values back into graph variables. The engine reads some of them, such as
`bIsSynced` and `iSyncIdleLocomotion` ([actor state](/engine/actor-state-graph.md)).

| Member | Written |
| --- | --- |
| `isActive` (output binding) | True on each update that reaches the machine. False on the update that first misses it |
| `currentStateId` (output binding) | The current state ID, on each update that reaches the machine |
| `m_syncVariableIndex` | The current state ID, when the index names a variable |

The sync variable is the same one that `m_startStateMode` 1 reads on entry. So two machines that
share it enter the state that the other one last published.

A deactivated machine does not overwrite `isActive` when another node wrote that variable in the
same update. This keeps a machine that stopped from hiding the value of one that started.

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
- With `FLAG_FROM_NESTED_STATE_ID_IS_VALID`, the machine inside the current state is in
  `m_fromNestedStateId`.

Of the candidates that can fire, the highest `m_priority` wins. At equal priority, the state's own
transition beats a wildcard. After that, array order wins. No source consulted documents Havok's
own tie-break, so this order is a choice. A total order keeps two instances stepping the same way.

### Global wildcards

A wildcard with `FLAG_IS_GLOBAL_WILDCARD` (`0x400`) also fires while its own machine is not
active. Each active machine above it looks for global wildcards below its other states. When one
can fire, that machine moves into the state that holds the nested machine. The nested machines then
start in the states on the path, and the last one starts in the wildcard's `m_toStateId`. The
machine checks this only when none of its own transitions fire. A wildcard with only
`FLAG_IS_LOCAL_WILDCARD` (`0x800`) fires only while its machine is active.

Evidence from the install: in `0_master.hkx`, no `Master_Behavior` transition targets
`Cart_State`. The `Cart` machine inside it has seven wildcards with flags `0xd00`, among them
`IdleCartPrisonerCIdle`, `IdleCartDriverIdleStill`, and the five sway events. The other cart
events carry `0x900`, without the global bit. The open sources name the bit but do not describe
Havok's exact rule. The path rule above is ours, and it is what makes the player's seat idle reach
`Cart_State`.

The state changes when the transition starts: `currentStateId` becomes the destination, the exit
and enter events fire, and the effect only fades out the old pose. `FLAG_DELAY_STATE_CHANGE`
postpones that: the source state stays current until the effect ends. It is set on 14 of the
3,769 transitions in the vanilla player graph. A transition with no effect ends every blend and
switches at once.

An event that arrives during a crossfade can start a new transition. The new effect fades from the
running blend, which keeps running and advancing, to its own target. At most
`m_maxSimultaneousTransitions` run at once; the oldest ends first. A running transition refuses the
new one when:

- it has `FLAG_UNINTERRUPTIBLE_WHILE_PLAYING`, or
- the new one has a lower `m_priority`, or
- it is a delayed state change with `FLAG_UNINTERRUPTIBLE_WHILE_DELAYED`.

Entering a state starts its generator from the beginning, even when the old state is still
blending out of it. Nodes that the old state also runs keep their state. The swinging blade trap
(`meshes\traps\swingingblade\trapbladeswinging01.hkx`) shows why. Its script waits for `Reset`
at the end of the swing and raises `Single` again in the next update. That update still blends
out of the finished swing. Without the restart, the swing clip stays at its end. In the game,
the blade swings again and again. This is observed behaviour; no Havok source describes it.

The four machine-level event IDs are checked only when no transition fired:

- `m_returnToPreviousStateEventId` goes back one state, when there is one and it differs from the
  current one. A transition with `FLAG_DISALLOW_RETURN_TO_PREVIOUS_STATE` cannot be returned
  through.
- `m_transitionToNextHigherStateEventId` and `m_transitionToNextLowerStateEventId` step through the
  sorted state IDs, and respect `m_wrapAroundStateId`.
- `m_randomTransitionEventId` picks one of the transitions that could fire from the current state
  and the wildcards, leaving out those with `FLAG_DISALLOW_RANDOM_TRANSITION`. The pick is by the
  target state's `m_probability`, against a draw `u / 2^32` from the generator
  `u' = u * 1664525 + 1013904223`. Mode 2 start states draw from it too. Each instance has its own
  generator. Its seed, `0x5EED`, is OpenSky's choice; the game seeds one per character. So two
  instances stepped the same way pick the same states.

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
| `0x8` | `UNINTERRUPTIBLE_WHILE_DELAYED` | Never set |
| `0x10` | `DELAY_STATE_CHANGE` | 14 |
| `0x20` | `DISABLED` | 2 |
| `0x40` | `DISALLOW_RETURN_TO_PREVIOUS_STATE` | Never set |
| `0x80` | `DISALLOW_RANDOM_TRANSITION` | Never set |
| `0x100` | `DISABLE_CONDITION` | 3,340, exactly the transitions with a null `m_condition` |
| `0x200` | `ALLOW_SELF_TRANSITION` | 75 |
| `0x400` | `IS_GLOBAL_WILDCARD` | 729, only in wildcard arrays |
| `0x800` | `IS_LOCAL_WILDCARD` | 1,167, only in wildcard arrays |
| `0x1000` | `FROM_NESTED_STATE_ID_IS_VALID` | 24 |
| `0x2000` | `TO_NESTED_STATE_ID_IS_VALID` | 642, only where the ID names a nested state |

`0x4000` is never set. The `0x100` match is the strongest evidence here. A bit
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
is counted (`transitionConditionUnparsed`, `transitionConditionUnresolved`). The game does the same.
It removes tabs and newlines, then compiles the text once, all or nothing. Text that fails gives no
result, and a condition with no result is false. No part of it counts, not even a valid `||` part.

One vanilla condition fails this way, in the game too:
`(staggerDirection < .25) || (staggerDirection > .75) || (staggerMagnitude > .3 , < .7)`. The comma
inside a plain parenthesis is an error, so that stagger transition never fires. The count stays,
because it also catches text the game accepts and this grammar does not.

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

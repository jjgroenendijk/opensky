---
type: Subsystem
title: Papyrus update timers
description: The Form update timer natives - four slots per instance, the two clocks, menu pause,
  catch-up and clock scrub rules, unload and save behavior, and the choices made where the wiki is
  silent.
tags: [engine, papyrus, game-clock]
---

# Papyrus update timers

Six `Form` natives register and clear update timers:

```papyrus
Form.RegisterForUpdate(float afInterval) native
Form.RegisterForSingleUpdate(float afInterval) native
Form.RegisterForUpdateGameTime(float afInterval) native
Form.RegisterForSingleUpdateGameTime(float afInterval) native
Form.UnregisterForUpdate() native
Form.UnregisterForUpdateGameTime() native
```

The timer registry sits beside the [VM scheduler](/engine/papyrus-vm.md#scheduler), not inside it.
A timer has an interval and a slot, never a suspended call.

## Slots

The first pair counts real seconds and fires `OnUpdate`. The second pair counts game hours and fires
`OnUpdateGameTime`. The plain calls repeat, and the `Single` calls fire once. So each instance has
four slots: real or game time, times repeating or single.

Registering into a slot replaces what it held. It never stacks and never touches the other three
slots. The [`RegisterForUpdate - Form`](https://ck.uesp.net/wiki/RegisterForUpdate_-_Form) page says
this for real time: "Subsequent calls to `RegisterForUpdate` will override previous ones ... It does
not interfere with updates registered via `RegisterForSingleUpdate`". OpenSky applies the same rule
to game time. The wiki does not describe that family separately.

`UnregisterForUpdate()` clears both real-time slots, and `UnregisterForUpdateGameTime()` clears both
game-time slots. The wiki does not say whether unregistering reaches the single slot, so OpenSky
clears the whole family, to match the register side.

A registration targets the exact instance behind the receiver. An opaque handle, such as an
unscripted reference or the player, has no instance to deliver to, so registering does nothing and
still returns `None`. An interval that is not finite, zero, or negative becomes zero. The wiki gives
no rule for this. A single timer then fires on the next fixed step, and a repeating one fires every
step.

## Firing

A due slot queues its event through the [event queue](/engine/papyrus-world.md#event-queue) at
activation depth 0. Slots due on the same step queue in registration order.

Both event pages say "This event will not be sent if the game is in menu mode"
([`OnUpdate - Form`](https://ck.uesp.net/wiki/OnUpdate_-_Form),
[`OnUpdateGameTime - Form`](https://ck.uesp.net/wiki/OnUpdateGameTime_-_Form)). OpenSky keeps that
rule through the clock, not a branch. Both families move only when the world runtime advances, and a
paused frame has a delta of zero, so it makes no fixed steps and both families wait.

Real-time slots use the scheduler's whole-tick count, so they do not drift. Game-time slots add
deltas from the game clock with the same policy the scheduler uses: a backward jump adds zero and
resets the baseline, and one step adds at most 24 game hours.

A due timer fires at most once per step, however many intervals passed. A repeating timer then
restarts from now instead of queueing one event per missed interval. Without this rule, one
`SetGameHour` jump from the `World > Runtime State` panel could fire a month of timers in one step.

## Unload and save

When a cell unloads, its non-persistent instances lose their timers, the same rule trigger
containment follows. A script that leaves the world with its cell does not carry timers forward
unseen. Persistent instances keep theirs, because they are never retired.

Timers of persistent instances are saved in the `PTMR` chunk, apart from `PSCR`, because a timer is
not a variable ([save chunks](/formats/save-chunks.md)). Each entry stores the time left, not a
deadline, and a restore starts it from the current tick and game hour. So time between save and load
never counts. A saved timer for an instance the session does not hold is counted as
`unknownSaveTimerTarget`, not a fault. Timers restore after instances, because each timer names its
instance.

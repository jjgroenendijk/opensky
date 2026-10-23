---
type: Subsystem
title: Global variables
description: How runtime GLOB values are stored beside reference state, the rounding rule for
  integer globals, the journal and callback split, and the one lookup seam every reader uses.
tags: [engine, world, globals, conditions, game-clock, runtime-state]
---

# Global variables

A [`GLOB` record](/formats/records.md) gives a name, a number type, and a default value. A session
then writes over the default, and conditions, scripts, and the game clock must all read what the
session last wrote. The overrides live in the [world state store](/engine/runtime-state.md).

## A map beside the components

A global is not placed anywhere. It has no cell, no transform, and no baseline a cell build derives.
Making it a reference component would put a value with none of a reference's properties into the
type that describes references. It would also write a new component tag into the `RDLT` save chunk,
where an unknown tag is a hard error, so an older build would refuse the save.

So the store keeps a map from key to global value beside the reference deltas. The key is still a
`ReferenceKey`: the `GLOB` record's own, resolved through its plugin's master list. Identity, order,
and save encoding are shared with references. Overrides are saved in the `GVAR` chunk.

## Types and rounding

A global value pairs a float with the `FNAM` type. Every value is converted to the type when it is
made, so a short or long global never holds a fraction, whoever wrote it: a script, a console
command, or a save. Float globals pass through.

Rounding is half away from zero: 3.7 becomes 4, and -2.5 becomes -3. No open spec states the
original rule, so this is OpenSky's choice. Truncation was rejected because it makes sums wrong in a
way players notice: adding 0.6 ten times to a short global gives 0 with truncation and 6 with
rounding. A non-finite value becomes 0 for an integer type, so no NaN reaches a comparison. Nothing
is limited to 16 or 32 bits, because `FLTV` is a float on disk and a mod may legally write large
values.

## Writes, resets, and the journal

- Writing the value already stored does nothing and returns false, like a component write.
- Reset removes the override, so the global reads its plugin default again. Resetting every global goes
  in key order, so the journal stays the same on every run.
- Every write and reset is journaled in its own bounded window, sharing the one sequence counter with
  component changes. Merging the two by sequence gives the real causal order.
- Global writes fire their own callback, not the reference change callback. The reference callback
  rebuilds cells, and a global changes a number, not a scene. The clock writes `GameHour` every
  frame, and routing that through cell rebuilds would rebuild every loaded cell every frame.

## The lookup seam

One seam answers what a global is worth. It pairs the plugin defaults with the session overrides,
and its order is fixed: the session override wins, the plugin default is next, and no answer means
the form ID names no known global. It can be built from the live store or from a snapshot, so a
reader off the main actor gets the same answers without touching the store.

It answers four questions: the value with its type, the number alone (the clock reads `TimeScale`
this way), the right side of a `CTDA` comparison, and whether the session has written the global.

A seam built with the [game clock](/engine/game-clock.md) answers the five time globals from the
clock, ahead of any override. Writing one of those globals moves the clock instead. It is journaled
on the globals ring, stores no override, and does not fire the global callback, so moving the time
does not roll the weather again. The game clock page explains why the clock owns time.

For a `CTDA` comparison ([conditions](/formats/conditions.md)), a literal passes through and a global
operand resolves through the seam. No answer means the condition names a global nothing defines. The
evaluator treats that as a failure, not as a comparison with zero
([condition evaluation](/engine/conditions.md)).

The first reader was weather: each climate weather chance can name a global, so changing that global
changes which weather the pick returns ([weather](/engine/weather.md)). The weather store stays
read-only. A new seam is handed to it on every global change, and it picks again.

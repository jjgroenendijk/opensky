---
type: Subsystem
title: Papyrus activation and world natives
description: How the use key reaches OnActivate, trigger events, the main-actor world bridge that
  every world native goes through, the activation recursion cap, and the ObjectReference,
  GlobalVariable, and Game natives with their stated gaps.
tags: [engine, papyrus, interaction, runtime-state]
---

# Papyrus activation and world natives

This page covers how scripts hear about the world and how natives change it. The VM is on the
[Papyrus VM](/engine/papyrus-vm.md) page and the engine loop on the
[world runtime](/engine/papyrus-world.md) page.

## The player's handle

The player is not a plugin reference here, so its identity is `ReferenceKey.player`
([reference identity](/engine/reference-identity.md)). It is the activator recorded on an
activation and the `akActionRef` a script receives.

A reference with scripts is passed as its live instance handle, the same one `VMAD` properties bind
to. Any other reference, the player included, gets an opaque handle, cached for the session. Opaque
handles count down from `UInt64.max` and instance handles count up from 1, so the two never meet.
Both resolve back to a `ReferenceKey`. A reference that gains an instance after it got an opaque
handle keeps both. Both resolve to the same key, so world writes stay right. Only comparing handles
inside a script could tell.

## OnActivate

Activation queues `OnActivate(ObjectReference akActionRef)` on every script on the target, in
instance key order, with the activator as argument 0. A target with no scripts queues nothing, and
the activation is still recorded.

The use key goes through [interaction](/engine/interaction.md). The handler maps the event's form ID
to a `ReferenceKey`, records the activation with the player as activator, and queues `OnActivate`.
The open flag is set only for a door-style open action.

## OnTriggerEnter and OnTriggerLeave

A trigger edge queues `OnTriggerEnter` or `OnTriggerLeave` on every script on the volume's reference,
with the actor as argument 0. The player's own occupancy resolves to `ReferenceKey.player`, and an
NPC passes its own key. These events are not an activation chain: occupancy comes from the
streamer's per-frame test, not from scripts, so a handler cannot cause another edge. They never use
the recursion cap. Where occupancy comes from is on the
[collision world](/engine/collision-world.md) and [trigger volumes](/engine/trigger-volumes.md)
pages.

## The world bridge

The Papyrus VM, its natives, the world state store, and the world runtime all run on the main actor.
The compiler checks this, so a native needs no runtime hop to reach the world. The VM runs from the
frame tick, and the headless CLI runs on the main actor too. The bridge joins natives to the world:

- A main-actor protocol lists every world operation a native may do: handle and key lookup, resolved
  reference state, the decoded reference, its resident cell, one component write, global reads and
  writes, and activation. Natives hold it as `context.world`.
- The production conformer writes through the world state store, so the journal, the dirty counts,
  and the save see every change. A write names the reference's resident cell when known, so only that
  cell rebuilds.

A headless runtime has no world, so a native that needs one fails cleanly. The registry inside the
runtime owns the bridge, so the bridge holds the runtime and the streamer weakly.

## Activation recursion cap

A script that activates a reference whose `OnActivate` activates it back would loop forever, one
round per tick. So each event has an activation depth. The use key queues at depth 1. An activation
made while running a depth *n* event queues at *n + 1*. Every other event is at depth 0. Past depth
8 nothing is queued or recorded, and the tally counts a capped activation.

A latent handler that resumes on a later tick has lost its depth and continues at 0. The per-tick
event budget still bounds the cost.

## World natives

`ObjectReference`, `GlobalVariable`, and `Game` share one policy. Each takes `self` from the call's
receiver and turns it into a `ReferenceKey`. No world, an unknown receiver, or no receiver is a
failure with a reason, not a guess. Each change is one world state write.

A write does not need the reference to be loaded. A script may disable something in a cell nobody
has streamed, and the change waits in the store. A read that needs the plugin baseline does need it:
`IsEnabled`, the position getters, and `SetPosition`, which keeps the rotation, the `XSCL` scale, and
any axis it is not given.

`GetLinkedRef` reads the `XLKR` list. With a keyword it returns the first link with that tag, and
with `None` the first link with no tag. Every no-answer case returns `None`. `XLKR` stores its
keyword as a load-order-relative form ID, so each tag is resolved through the session's resolver and
compared as a key. A tag the session cannot name never matches.

`Activate` records an activation and nothing else. It never casts the interaction ray. The activator
is argument 0, or the player when the argument is missing, `None`, or a handle with no world
identity. It returns false only when the recursion cap refused it.

`GlobalVariable` writes round short and long globals on every write
([global variables](/engine/global-variables.md)). `GetValueInt` truncates toward zero and saturates
at the `Int32` bounds. Reads fail for an unknown global, because zero is a value a script would act
on. Writes do not fail, because with no global store the first write creates the override.

`Game.GetPlayer` returns the player's handle, stable for the session, so the usual
`akActionRef == Game.GetPlayer()` check works.

## Stated gaps

| Behavior | What OpenSky does | Why |
| --- | --- | --- |
| `Enable(abFadeIn)`, `Disable(abFadeOut)` | Ignores the fade | There is no fade. The reference changes on the next cell rebuild, and the state is the same either way |
| `Activate(_, abDefaultProcessingOnly)` | Ignores the flag | This path has no built-in activation behavior to limit |
| `Activate` and the open state | Never opens | Only the use key knows the action was an open. A scripted activation records itself without claiming the target opened |
| `TranslateTo`, `TranslateToRef`, `SplineTranslateTo` | Not installed | Moving over time and `OnTranslationComplete` need a mover the runtime does not have |
| `XESP` enable parents | Not followed | `Enable` and `Disable` act on the receiver alone |
| A constant global | Written anyway | The Creation Kit rule stops editing a constant in the editor. Nothing open says the engine refuses a scripted write |
| `Delete` | Writes the change at once | The wiki says it waits until nothing holds the reference. OpenSky has no reference counting |
| `PlayAnimation` and its two siblings | Return true with no effect | Counted as a deferred animation, not treated as done |

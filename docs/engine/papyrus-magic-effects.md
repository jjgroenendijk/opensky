---
type: Subsystem
title: Papyrus magic effect scripts
description: How a magic effect's scripts run while the effect runs on an actor - where the start
  and end come from, the events and natives, and where OpenSky differs from the game.
tags: [engine, papyrus, magic]
---

# Papyrus magic effect scripts

A magic effect record (`MGEF`) can carry scripts in its `VMAD` field. Each script extends
`ActiveMagicEffect`. The game makes an instance of each script when the effect starts on an actor,
and drops it when the effect ends. Sources: the Creation Kit wiki pages
[ActiveMagicEffect Script](https://ck.uesp.net/wiki/ActiveMagicEffect_Script),
[OnEffectStart](https://ck.uesp.net/wiki/OnEffectStart_-_ActiveMagicEffect),
[OnEffectFinish](https://ck.uesp.net/wiki/OnEffectFinish_-_ActiveMagicEffect), and
[OnMagicEffectApply](https://ck.uesp.net/wiki/OnMagicEffectApply_-_ObjectReference).

## Where the start and the end come from

[Active effects](/engine/magic.md) live in the world-state store, one list per actor. Each effect has
a per-actor application number. Every change to the list is a journal entry. Each frame, the
Papyrus bridge reads the active-effect entries since the last frame, like the
[item events](/engine/papyrus-world.md#item-events):

- A number in the new list but not in the old one is an effect that started.
- A number in the old list but not in the new one is an effect that ended, by expiry or by a dispel.

The magic code does not know about scripts. It only writes its own state.

## Events

For an effect that started, in this order:

1. `OnMagicEffectApply(akCaster, akEffect)` goes to every script on the target that handles it.
2. Each script of the `MGEF` gets an instance, then `OnInit`, then
   `OnEffectStart(akTarget, akCaster)`.

For an effect that ended, each instance that served it gets `OnEffectFinish(akTarget, akCaster)`.
An instance that serves no other effect then retires, once its queued events have run. A potion
that nobody cast has `None` as the caster.

An instance sits on the target actor, so the target's other events, such as `OnHit` and
`OnItemAdded`, reach it too. The game does the same. Effect instances never answer as the actor's
own `ObjectReference` script, and they never pair with a form or alias script as a sibling.

## Natives

| Native | Answer |
| --- | --- |
| `ActiveMagicEffect.GetTargetActor` | The actor the effect runs on |
| `ActiveMagicEffect.GetCasterActor` | The caster, or `None` |
| `ActiveMagicEffect.GetBaseObject` | The `MGEF` |
| `ActiveMagicEffect.Dispel` | Removes this one effect; `OnEffectFinish` follows on the next frame |
| `ActiveMagicEffect.RegisterForAnimationEvent` | As the `Form` version |
| `MagicEffect.GetAssociatedSkill` | The skill name of `MGEF` `DATA` magic skill, or `""` |

The update-timer natives on `ActiveMagicEffect` work as on `Form`
([timers](/engine/papyrus-timers.md)).

## Where OpenSky differs from the game

- An instance is keyed by the target and the script name. Two runs of one effect on one actor
  share one instance, which gets `OnEffectStart` twice. It retires when the last run ends. In the
  game, each run has its own instance.
- An effect with zero duration is applied once and never stored, so its scripts never run. In the
  game, its scripts get `OnEffectStart` and then `OnEffectFinish`.
- An effect whose archetype OpenSky does not apply yet is not stored, so its scripts do not run.
- Effect instances are not saved. After a load, the effects that still run have no script
  instances, and their end sends no `OnEffectFinish`.

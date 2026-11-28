---
type: Subsystem
title: Shouts
description: How the player's shout key, the behaviour graph, and the shout records work
  together; how words are learned and unlocked with dragon souls; how the cooldown is timed;
  and where OpenSky differs from the game.
tags: [engine, magic, shouts, behaviour-graph, perks]
---

# Shouts

A shout (`SHOU`) has up to three words of power (`WOOP`). Each word has its own spell and its
own recovery time ([shout records](../formats/shouts-equip-slots.md)). The player shouts with the
shout key: a tap shouts the first word, and a longer hold shouts more of the unlocked words.

## Sources

- UESP "Skyrim:Dragon Shouts" (<https://en.uesp.net/wiki/Skyrim:Dragon_Shouts>): "Tapping the
  shout button will unleash the weakest version of the shout, holding it down briefly will release
  the middle version, and simply holding the button will unleash the most powerful available
  version of the shout. Once the shout is fully charged, your character will release it
  automatically."
- UESP "Skyrim:Fortify Shouts" (<https://en.uesp.net/wiki/Skyrim:Fortify_Shouts>): a magnitude of
  0.2 "reduces the `ShoutRecoveryMult` actor value from its base value of 1.0 to 0.8".
- The install's `0_master.hkx` and `shout_behavior.hkx`, the `AllowShoutingPerk` record, the
  `fShoutTime1` and `fShoutTime2` settings, and the `Shout` row of `controlmap.txt`. All were read
  with `openskycli`.

## What the player knows

The Papyrus shout natives keep the player's words and shouts in the script state ([script
state](papyrus-script-state.md#words-and-shouts)).

- A shout is known when `Actor.AddShout` gave it, or when one of its words is known.
- Words unlock in order. The shout can use the words from the first one up to the first locked
  word.
- Unlocking a learned word spends one `Dragon Souls`, the same actor value the Dragonborn altar
  spends.

The Shouts section also shows how fast the world and the player run while a Slow Time effect is
on the player ([Slow Time](magic-archetypes.md#world)).

## Magic menu

The magic menu lists each known shout under `sShouts`, and in the first tab, by name. The
equipped shout is marked. Accept equips the selected shout. While a shout is under way the
equip is refused with `sFailShouting` ("You cannot change shouts while shouting.").

The left-hand key unlocks the next learned word of the selected shout. With a dragon soul it
asks `sConfirmSpendSoul` ("Spend Soul?") with Yes and No, and Yes spends one. With none, the HUD
shows `sFailSpendSoul` ("Dragon Souls are required to unlock shouts."). A shout with no learned
word left to unlock takes the key as an equip. The game binds unlocking to its own key; which
key is not confirmed.

## One shout, step by step

1. The key goes down. The shout is refused when Mod Shout OK (entry point 82) is not above 0, when
   the cooldown runs, when no shout is equipped or none of its words is unlocked, or when a hand
   casts. Entry point 82 starts from 0; `AllowShoutingPerk` adds 1 once its quest stage is done.
2. While the player inhales, the engine writes `bWantCastVoice` true. `0_master.hkx` turns the
   rise into `BeginCastVoice` with a `BSEventOnFalseToTrueModifier`, and the graph plays the
   inhale.
3. The key comes up, or the hold reaches the last unlocked word. The engine raises
   `shoutRelease`, and the graph plays the exhale.
4. The exhale clip raises `Voice_SpellFire_Event` (two clips spell it `Voice_Spellfire_Event`).
   The spell of the shouted word fires on that frame, at full power and with no magicka cost.
5. The cooldown is the word's recovery time times `Shout Recovery Mult`, whose base is 1.

The hold picks the words: below `fShoutTime1` (0.2 s) one word, below `fShoutTime2` (0.9 s) two,
and three after that, but never more than are unlocked.

[WARNING] No source says how the game uses `fShoutTime1` and `fShoutTime2`. OpenSky reads them
as the holds that reach the second and third word. The values fit the UESP text above.

## An NPC shout

The Shout package procedure (<https://ck.uesp.net/wiki/Shout_(Procedure)>) needs a shout record
and a target; a generic shout type is matched against the actor's own spells, and with no match the
procedure fails. Until there is a target, it waits. Each update it looks at the target and equips
the shout. It is ready when:

- without Just Headtrack, the actor stands at the location and faces the target within
  `fAIShoutToleranceDegrees` (5°);
- with Just Headtrack, the head aims at the target within 5°;
- with Hold When Blocked, no other live actor stands nearer than the target within
  `fAIAimBlockedToleranceDegrees` (10°) of the line to it.

Once ready, and when the voice is free, the actor casts the word of its chosen word count (1 to 3)
at the target. The procedure then waits for the spell to fire and the voice to be free, and is
done. After `fAIShoutRetryDelaySeconds` (4 s) with nothing happening, it tries again.

The cast runs this way:

1. The actor plays the voice action. For a dragon the idle tree picks `shoutStart`, or
   `shoutStartFireball` by a condition.
2. The graph raises `BeginCastVoice`. After `fShoutTime1` (0.2 s) the first word is reached, and
   after `fShoutTime2` (0.9 s) the second or third. An NPC takes the word count it chose; only the
   player holds the key.
3. At each word the actor speaks a line of the combat voice power topics. This is where a dragon's
   shouted words come from.
4. `Voice_SpellFire_Event` from the exhale clip fires the spell, and the recovery starts. The event
   in the wrong step, or with no spell, stops the cast.
5. A shout that has not fired after `fShoutTimeout` (8 s) is cancelled.

## Rumble

A shout rumbles every controller with haptics, when the Gameplay page's Vibration switch is on.
Each word count has its own `fShoutRumble{Big,Small}Motor{Duration,Frequency}V1` to `V3`. The big
motor plays on the left handle and the small one on the right; a pad with one actuator plays the
stronger of the two. The frequency setting is used as the strength, which is OpenSky's reading.
`openskycli game state player` shows the last rumble under `lastRumble`, with its `cause`
(`shout` or `weapon`), and the sound motors under `soundRumble`. Weapons and sounds rumble too
([sound mix](sound-mix.md#rumble)).

## Where OpenSky differs from the game

- A save keeps the time left of the cooldown, on the player's script state
  ([SCRS](../formats/opensky-save-world-chunks.md#scrs-script-state)), not its full length. The
  readout after a load shows the time left as the length.
- When no graph raises `Voice_SpellFire_Event` within 1.5 s of the release, the spell fires
  anyway. This keeps a shout working on a body with no graph. The game has no such wait.
- The graph picks the exhale clip; the engine does not tell it how many words were shouted.
- Only the player shouts. An NPC's shout package is not cast, so a dragon in a scene neither
  shouts nor speaks its words.

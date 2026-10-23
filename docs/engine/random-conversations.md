---
type: Subsystem
title: Random conversations and NPC social events
description: How NPCs decide to talk to each other, greet each other, and find bodies, which
  sends the ADIA, AHEL, and DEAD story events.
tags: [engine, ai, dialogue, story-manager]
---

# Random conversations and NPC social events

NPCs in the game talk to each other, say hello in passing, and react to a dead body. Each of
these sends a [story-manager](/engine/story-manager.md) event, and vanilla quests start from
them: `ADIA` (actor dialogue), `AHEL` (actor hello), and `DEAD` (dead body). The quest then
plays the conversation as a [scene](/engine/scenes.md) or a line.

Sources: the Creation Kit pages "Scene" (section "Controlling Random Conversations"),
"Actor Dialogue Event", "Actor Hello Event", and "Package" (the interrupt flags). The CK site
answers with a bot check, so the pages were read through the Wayback Machine.

## Who takes part

An actor takes part when it is loaded, alive, not the player, and not held by a playing scene.
Its current package decides what it may do. The package `PKDT` interrupt flags:

| Flag | Meaning |
| --- | --- |
| 0x01 | Hellos to the player |
| 0x02 | Random conversations |
| 0x04 | Observe combat behaviour |
| 0x08 | Greet corpse behaviour |

An actor with no package takes part in nothing.

## Settings

The CK names these game settings. `Skyrim.esm` overrides most of the wiki's values:

| Setting | Wiki | `Skyrim.esm` | Meaning |
| --- | --- | --- | --- |
| `fAISocialRadiusToTriggerConversation` | 2000 | 500 | Furthest target, exterior |
| `fAISocialRadiusToTriggerConversationInterior` | 1000 | 500 | Furthest target, interior |
| `fAISocialchanceForConversation` | 25 | 10 | Percent chance per try, exterior |
| `fAISocialchanceForConversationInterior` | 25 | 10 | Percent chance per try, interior |
| `fAISocialTimerForConversationsMin` | 30 | 10 | Shortest wait between tries, seconds |
| `fAISocialTimerForConversationsMax` | 60 | 30 | Longest wait between tries, seconds |
| `iAISocialDistanceToTriggerEvent` | 120 | 200 | How close the pair must be |
| `fAItalktosameNPCTimer` | 120 | not set | Seconds before the same pair talks again |

OpenSky reads the plugin value and falls back to the wiki value.

## The rules

The pass runs every 30 frames on the loaded actors. No `ADIA` or `AHEL` fires while the player
is in a conversation, because the CK says random conversations wait for important ones.

- `ADIA`: each actor whose package allows random conversations has a timer, rolled between the
  two timer settings. When it runs out, the actor rolls the chance. On success it picks the
  nearest valid partner within the radius, and the event fires when the partner is within the
  trigger distance. The same pair waits `fAItalktosameNPCTimer` seconds before another one.
  `R1` is the speaker and `R2` the partner.
- `AHEL`: an actor that moved at least 8 units since the last pass, and whose package allows
  random conversations, passes a standing free actor within the trigger distance. The same
  pair waits the same time. `R1` is the walker and `R2` the actor greeted.
- `DEAD`: an actor whose package greets corpses has a clear sight line to a dead actor within
  the social radius. Each finder and body pair fires once. `R1` is the finder and `R2` the
  body.

## Where OpenSky differs

- In the game an actor walks toward its partner before the conversation. OpenSky has no walk,
  so `ADIA` fires only when the pair already stands within the trigger distance.
- No setting names how far an actor sees a body. OpenSky uses the social radius.
- The timers, the pairs that talked, and the bodies found are not saved. A loaded game starts
  the timers again.
- Observing combat is not known yet, so flag 0x04 does nothing.

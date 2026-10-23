---
type: Subsystem
title: Survival Mode prompt
description: When the Survival Mode plugin asks its question, how OpenSky answers it ahead of
  time from the settings or a launch option, and how the answer stays in step with the plugin.
tags: [engine, settings, scripting]
---

# Survival Mode prompt

The Creation Club plugin `ccQDRSSE001-SurvivalMode.esl` asks the player once whether to turn
Survival Mode on. OpenSky lets the player answer ahead of time, so the question does not stop a
new game or an agent session.

## When the plugin asks

The engine does not ask. The plugin's quest script `Survival_MainScript` asks. Its rules, read
from the compiled script in the plugin's archive:

1. `OnInit` registers for an update in 5 seconds. Each `OnUpdate` registers the next one.
2. Each update calls `PromptToStartSurvivalMode`. It shows the message `Survival_StartPrompt`
   only while the global `Survival_PlayerHasBeenPrompted` is 0 and `ModeCanBeEnabled()` is true.
3. `ModeCanBeEnabled()` is true when the quest `MQ101` is completed, or when
   `Game.IsFightingControlsEnabled()` is true and the player is not in an interior. It writes the
   result to `Survival_ModeCanBeEnabled`.
4. Button 0 (Yes) sets `Survival_ModeToggle` to 1. Either button then sets
   `Survival_PlayerHasBeenPrompted` to 1.
5. The same update starts the mode when `Survival_ModeToggle` is 1 and the mode may be enabled,
   and stops it when the toggle is 0. `Survival_ModeEnabled` says whether it runs.

So in a vanilla new game the question comes after the opening, the first time the player is
outdoors with fighting controls on. A start in an exterior cell, or a teleport out of the
opening, meets the rule at once, so the question comes within 5 seconds. This is the plugin's
own rule, not an OpenSky choice.

The plugin's Default Objects name three of the globals:

| Tag | Name in the Creation Kit | Global |
| --- | --- | --- |
| `SRVT` | Survival Mode - Toggle | `Survival_ModeToggle` |
| `SRVE` | Survival Mode - Enabled | `Survival_ModeEnabled` |
| `SRVS` | Survival Mode - Show Option | `Survival_ModeCanBeEnabled` |

Source: the plugin's `DOBJ` and `GLOB` records and `survival_mainscript.pex`, read from the
user's install. The tag names come from the `DOBJ` tag list in xEdit.

## Answering ahead of time

Two player settings hold the answer:

- `gameplay.survivalMode`, the Gameplay page's Survival Mode toggle: on or off.
- `opensky.survivalModeAsk`: when on, a new game asks as the plugin does.

Both are off by default, so a new game starts with Survival Mode off and no question. The
launcher's Launch page shows both as checkboxes in its New game group.

`OPENSKY_SURVIVAL_MODE` (`on`, `off`, or `ask`) wins over both settings for one run.
`openskycli game launch --survival-mode` sets it, and its default is `off`
([agent control](/tools/agent-control.md)).

Before the scripts run in each frame, OpenSky reads the globals:

- No answer yet and the answer is on or off: it writes what a press of Yes or No writes. The
  toggle gets the answer, and `Survival_PlayerHasBeenPrompted` gets 1. The plugin's state is
  then the same as if the player had chosen.
- No answer yet and the answer is ask: nothing. The plugin asks at its own moment.
- An answer that differs from the setting: the setting takes the session's answer. This covers
  a Yes in the plugin's question and a save loaded with the mode on.

The plugin starts or stops the mode at its next update, as the question's text promises.

Without the plugin, none of the globals exist, and nothing happens.

## Differences from the game

- The game keeps the answer only in the save. OpenSky also keeps it in the settings, so a new
  game uses the last answer.

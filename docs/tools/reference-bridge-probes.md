---
type: Tool
title: Reference bridge probes
description: Bridge commands that click a reference-game menu, play a movie, record sound, and
  record behaviour graph variables.
tags: [tools, reference, bridge]
---

# Reference bridge probes

These commands use the bridge plugin in the Windows reference game
([reference game](reference-game.md#the-bridge-plugin)). They read or drive one part of
the game for a comparison with OpenSky.

## Clicking a menu and playing a movie

Mouse clicks sent from macOS do not reach the game under Wine. Bridge lines reach the game's
interface from inside instead. A field list is split by `|`, because menu names hold spaces.

| Line | What it does |
| --- | --- |
| `menumove <menu>\|<x>\|<y>` | Moves the menu movie's cursor to that stage point |
| `menudown <menu>\|<x>\|<y>` | Presses the left button there |
| `menuup <menu>\|<x>\|<y>` | Releases the left button there |
| `menuhit <menu>\|<x>\|<y>` | Only tests the point: is a shape under it, and is a mouse target under it |
| `menuvar <menu>\|<path>` | Reads one ActionScript value of the menu's movie, such as `_x` of a clip |
| `playbink <file>[\|<flags>]` | Calls the script function `Game.PlayBink`; four optional `0` or `1` fields set its flags |
| `menuopen <menu>`, `menuclose <menu>` | Shows or hides a menu, such as `TweenMenu` or `Journal Menu`, as the game's own key for it does |
| `menucall <menu>\|<path>\|<argument>...` | Calls one ActionScript function of the menu's movie. A number, `true`, or `false` passes as that type, anything else as text |
| `automove on`, `automove off` | Holds or ends Auto-Move, so the player walks forward with no key pressed |

The movie finds the target under the cursor once per frame. So a click is three batches, one
line each: move, then down, then up. Sent in one batch, the press reaches nothing. The click
goes through the movie's own hit test, as a real click does. `state.json` lists each value a
`menuvar` line read under `menuValues`, keyed by `<menu>|<path>`, the last mouse line under
`menuClick`, with its window point and the two hit tests, and the last `menucall` under
`menuCall`, with its `result`. `openMenus` names every open menu, and `autoMove` says whether
Auto-Move is held. A stage point is in the movie's own
pixels; at the default 1280 x 720 window it is the same as the window point. For example, to
click the race menu's right category arrow:

```sh
openskycli reference send 'showracemenu'
for step in move down up; do
  openskycli reference send "menu$step RaceSex Menu|700|38"
done
```

The `playbink` flags are, in order, interruptible, mute the other sound, mute the music, and
letterbox. They default as the script does: `0|1|1|1`.

`openskycli reference listen` records what the game plays, for a check by ear or by
comparison with a sound file. Two recordings cannot run at the same time: the second one waits
forever.

## Recording graph variables

Two more bridge lines let a batch set up a scene and record an actor's behaviour graph:

| Line | What it does |
| --- | --- |
| `spawn <FormID>` | Places that base object at the player and picks the new reference |
| `watch <seconds> <variable>...` | Records the picked reference, or the player with no pick, each frame |

`watch` writes `OpenSkyBridge/watch.jsonl` when it ends. Each frame gives one line with the
time, the frame length, the position, the heading, and each variable as `[real, int, bool]`.
The game stores every variable as one word, so read the field that matches the variable's
type. Each animation event the actor sends gives one line with its tag and payload. Start the
watch once the actor is loaded: events from a graph built after the watch starts are lost.

`state.json` names the spawned reference under `selected`, so a second actor can be spawned
and its FormID used in `startcombat`. For example, to record a melee bandit fighting a mage:

```sh
openskycli reference send 'spawn 1BCD8' 'setav health 100000'
openskycli reference send 'spawn 39D33' 'setav health 100000' "startcombat $MELEE" \
  "prid $MELEE" "startcombat $MAGE" 'watch 45 iState IsAttacking IsInCastState'
```

[WARNING] Nothing drives the player's attacks or casts yet. Button events the plugin sent
through the game's input device manager did not move the player under Wine (observed
2026-11-04), so a recording of the player shows it at rest.

The bridge also reports the sky, the music, the player's location, and a map marker it can
move the player to. [Reference sky and music](reference-sky-music.md) describes them.

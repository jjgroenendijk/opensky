# openskycli game command reference

Sections: options, session, time, input, state, debug, events, scripts.

Every call: `openskycli game <command> [--text] [--socket <path>] [--reply-timeout <s>]
[--record <file>]`. Exit code 0 when `ok` is true, 1 on a game error or no server, 2 on
a usage error.

## Session

| Command | Does |
| --- | --- |
| `launch [--mode play\|developer] [--title] [--app <path>] [--wait <s>]` | Opens the app with the server on; waits for `worldReady`. `--title` opens on the main menu, as the launcher's Play button does |
| `attach` | Prints the hello line: protocol version, data root, `worldReady` |
| `status` | Running, mode, data root, frame, paused |
| `quit` | Quits the app after the reply |
| `screenshot [--out <png>] [--offscreen] [--size WxH] [--world-only]` | The window's next presented frame, debug view included. `--offscreen`, `--size`, or `--world-only` render a second frame instead |

## Time

`time pause`, `time resume`, `time step [n] [--seconds <s>]` (default 1/60 s per frame,
pauses first), `time scale <x>` (0 to 16, while running).

## Input

Actions: `forward back left right up down run sprint sneak jump activate attack block
readyWeapon cameraMode journal inventory map quicksave quickload pause menuUp menuDown
menuLeft menuRight menuAccept menuCancel`. `map` opens the world map, and `pause` opens the
System menu after an autosave. In a menu, `forward` and `back` move the selection like the
arrow keys.

- `input press <action>`, `input release <action>`
- `input hold <action> --frames <n>` or `--seconds <s>`; held actions only
- `input look --dx <deg> --dy <deg>`; positive dx turns right, dy looks up
- `input select <label>`: moves the open menu's selection to the row with that label
- `input point --x <0..1> --y <0..1>`, `input click --x <0..1> --y <0..1>`: moves the cursor
  over the open menu, or clicks there; fractions of the game view, origin top left
- `input text <text>`: types into the open menu that takes text, such as the race menu's
  name row after `menuAccept` on it

## State

`state player`, `state target`, `state actors [--radius <units>]`, `state menu`,
`state quest <editorID>`, `state av <name> [--ref <ref>]`, `state global <editorID>`,
`state scenes`, `state scripts [--ref <ref or quest editorID>]`, `state packages --ref <ref>`,
`state time`, `state frame`.

- `state player` also gives `firstPerson`: whether the arms graph and rig are attached and
  drawn, the failure reason, the arm model count, and the bones the last pose reached.
- `state quest` also lists each reference alias with the reference that fills it, or null.
- `state scenes` lists each playing scene with its quest, its current phase, and the phase's
  name.
- `state scripts` gives the script queue, the waits, the newest events, the newest fault, and
  the missing natives. With `--ref`, it also lists the scripts on that reference or quest
  with their state and variables.
- `state packages` gives the actor's package, its procedure, the procedure machine's state
  and patrol point, the mover's state, and the vehicle links.

A `<ref>` is `player`, `target` (the crosshair), or a hex FormID of a loaded reference.

## Debug

| Command | Example |
| --- | --- |
| `debug teleport --cell <editorID>` | `--cell WhiterunBanneredMare` (Skyrim.esm cells) |
| `debug teleport --x <n> --y <n>` | an exterior cell grid |
| `debug teleport --pos x,y,z` or `--ref <ref>` | inside the current cell; interior positions are local |
| `debug time <hour>` | `debug time 13.5` |
| `debug weather [<editorID>]` | no ID clears the forced weather |
| `debug av <name> --value <v>` or `--mod <d>` `[--ref <ref>]` | `debug av Health --value 50` |
| `debug item <editorID> [--count <n>]` | negative count removes; player only |
| `debug quest <editorID> <stage>` | sets a stage |
| `debug kill <ref>`, `debug resurrect <ref>` | not the player |
| `debug overlay <navmesh\|path\|detection\|hud\|ui> on\|off` | Also a render-debug layer: `statics`, `actors`, `distantlod`, `terrain`, `grass`, `water`, `sky`, `particles` |

## Events

`events` lists the ring buffer. `events --follow [--filter a,b] [--timeout <s>]` streams.
`events --until <kind> --timeout <s>` waits for the first event of that kind after the
call. Kinds: `cell.loaded cell.unloaded activation activation.refused menu.opened
menu.closed combat.hit actor.death quest.stage script.error log time.paused time.resumed`.

## Scripts

One JSON object per line; `#` lines are comments:

```text
{"command": "time.pause"}
{"command": "debug.av", "args": {"name": "Health", "value": 50}}
{"command": "state.av", "args": {"ref": "player", "name": "Health"}, "expect": {"value": 50}}
```

`expect` keys are dotted paths into `result`; numbers match within 0.0001.

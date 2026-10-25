# openskycli game command reference

Sections: options, session, time, input, state, debug, events, scripts.

Every call: `openskycli game <command> [--text] [--socket <path>] [--reply-timeout <s>]
[--record <file>]`. Exit code 0 when `ok` is true, 1 on a game error or no server, 2 on
a usage error. A misspelled or unknown option is a usage error, not ignored.

`openskycli game help` lists every command, and `openskycli game <command> --help` shows
one with its options. Both work without the app. A switch is `--x` or `--no-x` and takes no
value; a reference that a command acts on is a positional word, such as `debug kill <ref>`.

## Session

| Command | Does |
| --- | --- |
| `launch [--title] [--survival-mode on\|off\|ask] [--app <path>] [--wait <s>]` | Opens the app with the server on; waits for `worldReady`. `--title` opens on the main menu, as the launcher's Play button does, and waits for `titleMenuOpen` instead, because the main menu loads no world. `--survival-mode` answers the Survival Mode prompt ahead of time; the default `off` means the prompt never stops a session |
| `attach` | Prints the hello line: protocol version, data root, `worldReady` |
| `status` | Running, data root, frame, paused |
| `quit` | Quits the app after the reply |
| `screenshot [--out <png>] [--offscreen] [--size WxH] [--world-only]` | The window's next presented frame, debug view included. `--offscreen`, `--size`, or `--world-only` render a second frame instead |

To look at one record, reference, mesh, or cell without the game window, use
`openskycli preview` instead (`docs/tools/preview-render.md`).

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
- `input select <label>`: moves the open menu's selection to the row with that label; a
  message box's buttons count as rows, so `input select No` then `input press menuAccept`
  answers a question box
- `input point --x <0..1> --y <0..1>`, `input click --x <0..1> --y <0..1>`: moves the cursor
  over the open menu, or clicks there; fractions of the game view, origin top left
- `input text <text>`: types into the open menu that takes text, such as the race menu's
  name row after `menuAccept` on it

## State

`state player`, `state target`, `state actors [--radius <units>]`, `state menu`,
`state quest <editorID>`, `state av <name> [--ref <ref>]`, `state global <editorID>`,
`state scenes`, `state scripts [<ref or quest editorID>]`, `state packages <ref>`,
`state furniture [<ref>]`, `state objects [<ref>]`, `state changes [--limit <n>]`,
`state time`, `state frame`.

- `state player` gives the exterior `worldspace` and the current `weather` editor ID.
- `state player` gives the player `level`. `state actors` gives each actor's `leveled` roll: the
  `LVLN` `hops` (list and chosen entry), the `playerLevel` it rolls at, whether that level is
  `frozen`, the `encounterLevel`, and the `difficulty`. `debug skillsmenu --levelup <n>` raises
  the level; a frozen roll keeps its level until its cell resets (`debug rest 240` away from it).
- `state menu` on the skills menu adds `skills`: the `page` (`Closing` while `CameraOutro`
  plays), the stats `movie`, `levelUpMovie`, `skyEnabled`, and the `sky` line with its
  draw count, turn, and view (`ring`, `moving`, `tree view`, or `closing`).
- `state player` also gives `firstPerson`: whether the arms graph and rig are attached and
  drawn, the failure reason, the arm model count, and the bones the last pose reached.
- `state quest` also lists each reference alias with the reference that fills it, or null.
- `state scenes` lists each playing scene with its quest, its current phase, and the phase's
  name.
- `state scripts` gives the script queue, the waits, the newest events, the newest fault, and
  the missing natives. With `--ref`, it also lists the scripts on that reference or quest
  with their state and variables, and the `waits` they are in: the script, the native
  (`Utility.Wait`, `ObjectReference.PlayAnimationAndWait`), and what wakes it.
- `state player` also lists the `spells` the player knows, by editor ID, abilities such as
  `Rested` included.
- `state furniture` (default `player`) gives an actor's `sitState` (the `GetSitState` value),
  its furniture, marker, entry side, `position`, `sittingRotation`, and `leaving` while an exit
  clip carries it out, and its `idle`: the chosen clip, a failure, its seconds, and
  `rootMotion`; for a piece of furniture it gives the record's `rules` and lists each
  marker with its type, whether `MNAM` turns it on, its entry sides, its `position` and
  floor-level `root`, its holder, and `inUse`.
- `state objects` lists each running object behaviour graph, such as a trap's or a door's,
  with its project, innermost active `state`, every active state in `states`,
  `waitingForClip` while a clip it reached still loads, and events. With a ref it also gives
  `bones`: each bone's `position` in the object's own space and its `rotationDegrees` angle
  there, so two reads a few frames apart show a blade swing.
- `state changes` lists the newest world-state writes (`ref`, `kind`, `reset`) and whether a
  door transition or an interior rebuild is in flight. A cell that never settles shows the
  reference that keeps writing.
- `state packages` gives the actor's package, its procedure, the procedure machine's state
  and patrol point, the mover's state, and the vehicle links.

A `<ref>` is `player`, `target` (the crosshair), or a hex FormID of a loaded reference.

## Debug

| Command | Example |
| --- | --- |
| `debug teleport --cell <editorID>` | `--cell WhiterunBanneredMare` (any cell in the load order) |
| `debug teleport --x <n> --y <n> [--worldspace <editorID>]` | an exterior cell grid; `--worldspace DLC2SolstheimWorld` goes to another worldspace first |
| `debug teleport --pos x,y,z` or `--ref <ref>` | inside the current cell; interior positions are local |
| `debug time <hour>` | `debug time 13.5` |
| `debug weather [<editorID>]` | no ID clears the forced weather |
| `debug av <name> --value <v>` or `--mod <d>` `[--ref <ref>]` | `debug av Health --value 50` |
| `debug item <editorID> [--count <n>]` | negative count removes; player only |
| `debug quest <editorID> <stage>` | sets a stage |
| `debug kill <ref>`, `debug resurrect <ref>` | not the player |
| `debug racemenu [--limited]` | opens the race menu now, as the console's `ShowRaceMenu`; `--limited` is `Game.ShowLimitedRaceMenu` |
| `debug skillsmenu [--sky\|--no-sky] [--levelup <n>]` | opens the skills menu as the Quick Stats key does; `--sky` or `--no-sky` turns the perk sky on or off; `--levelup` first earns 1 to 10 character levels, so the level-up pick shows |
| `debug sit [<ref>] [--furniture <ref>]` | seats the actor (default `player`) in that furniture, or the nearest loaded one with a free seat |
| `debug stand [<ref>]` | gets the actor up from its seat |
| `debug rest <hours> [--sleep]` | passes 1 to 24 hours as the wait menu does, or the rest menu with `--sleep`, without the refusals |
| `debug overlay <navmesh\|path\|detection\|hud\|ui> on\|off` | Also a render-debug layer: `statics`, `actors`, `distantlod`, `terrain`, `grass`, `water`, `sky`, `particles` |
| `debug channel <mode>` | The scene pass's debug channel: `off`, `wireframe`, `worldnormals`, `texturecoordinates`, `miplevel`, `shadowcascade`, `layercategory` |
| `debug shadows <off\|low\|high>` | The sun shadow tier; it lasts until the renderer is rebuilt |

## Benchmark

| Command | What it does |
| --- | --- |
| `benchmark [quick\|standard\|full] [--scenes a,b] [--set id=v,id=v] [--no-overlay] [--no-load-passes] [--screenshots] [--windowed] [--capture <id>] [--out <absolute dir>]` | Flies the benchmark tour in the open window and replies when it ends, with the result folder, `comparable`, `stopped`, the failed scenes, and the summary |
| `benchmark --stop` | Stops a running tour; the scenes measured so far are kept |

The tour takes over the camera, the clock, and the HUD until it ends
(`docs/tools/benchmark.md`).

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

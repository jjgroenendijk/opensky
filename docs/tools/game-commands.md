---
type: Tool
title: openskycli game commands
description: Every command, input action, state read, debug command, and event kind that
  openskycli game sends to the running app, with its options.
tags: [tool, cli, agent-control, reference]
---

# openskycli game commands

`openskycli game <command>` drives the running app over its agent control socket
([agent control](/tools/agent-control.md)). This page lists what the app answers. The
[CLI page](/tools/cli.md) lists the other `openskycli` commands, and the
[reference game](/tools/reference-game.md) page lists the `reference` commands.

## Calling a command

Every call has this shape:

```sh
openskycli game <command> [--text] [--socket <path>] [--reply-timeout <s>] [--record <file>]
```

| Option | Does |
| --- | --- |
| `--text` | Prints `path: value` lines instead of JSON |
| `--socket <path>` | Talks to the app on this socket instead of the default one |
| `--reply-timeout <s>` | Seconds a command may wait for its reply |
| `--record <file>` | Records each request and reply in a JSONL script that `game run` replays ([scripts](#scripts)) |

| Exit code | Means |
| --- | --- |
| 0 | `ok` is true |
| 1 | The game answered with an error, or no app serves the socket |
| 2 | Usage error: an unknown command or option, or a bad value. Nothing was sent |

`openskycli game help` lists every command. `openskycli game help <command>` or
`openskycli game <command> --help` shows one with its options. Both read the app's own
catalog and work without the app. A switch is `--x` or `--no-x` and takes no value. A
reference that a command acts on is a positional word, such as `debug kill <ref>`.

A `<ref>` is `player`, `target` (the reference under the crosshair), or the hex FormID of a
loaded reference.

## Session

| Command | Does |
| --- | --- |
| `launch [--title] [--survival-mode on\|off\|ask] [--app <path>] [--wait <s>]` | Opens the app with the server on, or attaches to the running one, and waits for `worldReady`, 180 s by default. `--app` defaults to the build of this checkout. `--title` opens on the main menu, as the launcher's Play button does, and waits for `titleMenuOpen` instead, because the main menu loads no world. `--survival-mode` answers the Survival Mode prompt ahead of time; the default `off` means the prompt never stops a session |
| `attach` | Connects to the running app and prints the hello line: protocol version, data root, `worldReady` |
| `status` | Running, data root, frame, paused |
| `catalog` | Every command this app answers, with its arguments. The CLI parses against it |
| `run <script.jsonl>` | Runs a JSONL script and stops at the first failed line ([scripts](#scripts)) |
| `quit` | Quits the app after the reply |
| `screenshot [--out <png>] [--offscreen] [--size WxH] [--world-only]` | The window's next presented frame, debug view included. `--offscreen`, `--size` (16 to 8192 a side), or `--world-only` (no interface) render a second frame instead. `--out` takes an absolute path |

To look at one record, reference, mesh, or cell without the game window, use
`openskycli preview` ([preview render](/tools/preview-render.md)).

## Time

| Command | Does |
| --- | --- |
| `time pause` | Stops the clock. The game moves only when stepped |
| `time resume` | Starts the clock again |
| `time step [n] [--seconds <s>]` | Pauses first, then draws `n` frames, 1 to 100000 (default 1). A frame is 1/60 s unless `--seconds` sets it, up to 0.1 |
| `time scale <x>` | Runs the clock at `x` times its speed, 0 to 16, while running |

## Input

| Command | Does |
| --- | --- |
| `input press <action>` | Presses an action. A held action stays down until `input release`. `input press activate` is a tap: down and up in one frame |
| `input release <action>` | Releases a held action |
| `input hold <action> --frames <n>` or `--seconds <s>` | Holds an action while the game steps, then releases it: 1 to 100000 frames, or up to 600 s. Only for held actions and `activate`. Hold `activate` on a follower for command mode |
| `input look --dx <deg> --dy <deg>` | Turns the view. A positive `dx` turns right, a positive `dy` looks up |
| `input select <label>` | Moves the open menu's selection to the row with that label. A message box's buttons count as rows, so `input select No`, then `input press menuAccept`, answers a question box |
| `input point --x <0..1> --y <0..1>` | Moves the cursor over the open menu. The values are fractions of the game view, from the top left |
| `input click --x <0..1> --y <0..1>` | Clicks the open menu there |
| `input text <text>` | Types into the open menu that takes text, such as the race menu's name row after `menuAccept` on it |

| Action | Does |
| --- | --- |
| `forward`, `back`, `left`, `right` | Held. Moves. In a menu, `forward` and `back` move the selection like the arrow keys |
| `up`, `down` | Held. The camera's up and down move keys |
| `run`, `sprint` | Held. Movement speed |
| `sneak`, `jump` | Fires once on press |
| `activate` | Uses the reference under the crosshair |
| `attack`, `block`, `shout` | Held. Combat |
| `readyWeapon` | Draws or sheathes the weapon |
| `cameraMode` | Switches between first and third person |
| `journal`, `inventory`, `magic`, `skills`, `map`, `wait` | Opens that menu. `map` opens the world map |
| `placeMarker` | On the open world map, places, moves, or removes the custom marker at the map centre, as P does. A question it asks is a message box |
| `hotkey1` to `hotkey8` | Uses the favourite in that slot |
| `quicksave`, `quickload` | Saves or loads the quick save |
| `pause` | Opens the System menu after an autosave |
| `menuUp`, `menuDown`, `menuLeft`, `menuRight`, `menuAccept`, `menuCancel` | Moves in, accepts, or leaves the open menu |

## State

| Command | Gives |
| --- | --- |
| `state player` | The position, cell, exterior `worldspace`, the current `weather` editor ID, and the player `level`. The beast `form` (`none`, `werewolf`, `vampireLord`, or `otherBeast`) and the race `behaviorProject` the body runs, null for the character graphs, with `behaviorProjectFailure` when that project did not load. `melee`: the swing's `attackPhase`, `attackState` (the `GetAttackState` code, 4 inside a combo window after contact), `chainWindowOpen`, and `swingID`. Under `graph`: `drunk`, `iState`, and `perkState`, the perk state the graph tags (`NPCBowDrawnQuickShot` or `NPCBlockingShieldCharge`) or null. The owned `perks` and known `spells` by editor ID, abilities such as `Rested` included. `cloak`: `running`, `suspended` while its conditions fail (Shield Charge outside a charge), or `none`. `firstPerson`: whether the arms graph and rig are attached and drawn, the failure reason, the arm model count, and the bones the last pose reached. `staff`: the right-hand staff's `item`, `enchantment`, `charge`, and `capacity`, or null. `bowZoom`: `zoomed`, the `viewShare` of the normal view, the `timeScale` while zoomed, `fovYDegrees`, and `staminaPauseSeconds` left on the stamina regeneration pause |
| `state target` | The reference under the crosshair. `theft`: whether taking it now is theft |
| `state actors [--radius <units>]` | Each loaded actor near the player, within 4096 units by default. Its `leveled` roll: the `LVLN` `hops` (list and chosen entry), the `playerLevel` it rolls at, whether that level is `frozen`, the `encounterLevel`, and the `difficulty`. Its behaviour `graph`: `status` (`running`, `loading`, `failed: <reason>`, or `waiting for playback`), `project`, `activeStates`, `waitingForClip`, `hasPose`, `steps`, `rate`, `recentEvents`, `unresolvedClips`, `clipsLoaded`, `clipsMissed`, `drunk`, `iState`, `iStateTag` (the value the graph's state tagging generators publish), and `bodyWeight` (`weapAdj` and the body-weight layer weights the graph derives from it). Also `soundLoops`, the breath and movement loops it plays ([creature sounds](/engine/actor-sounds.md)), `skinDecals`, the bone each mark on it rides or `feet` ([skin decals](/rendering/decals.md#skin-decals)), `constraints`, `eyeTexture`, and `severed`: null while the head is on, else the cut `node`, the head's `headPosition`, `headResting` once its body sleeps, and `headDrawn` while the scene draws it. A rider or cart passenger has no graph until it gets off |
| `state menu` | The open menus and the selected rows. `hud`: whether the HUD movie is `loaded`, `cartMode`, and the `modes` stack the movie holds, bottom first, such as `["StealthMode", "CartMode"]`. On the skills menu, `skills`: the `page` (`Closing` while `CameraOutro` plays), the stats `movie`, `levelUpMovie`, `skyEnabled`, and the `sky` line with its draw count, turn, and view (`ring`, `moving`, `tree view`, or `closing`). On the system menu, `systemPage` (`main`, `help`, `installedContent`, and more) and `topic`, the title of the open Help or Installed Content topic. On the title menu, `credits`. Also `loading`, `bink`, `titles`, and `movie` (see the `debug` commands that set them). `map`: the open map's `mode` (`world`, `local`, or null), the `selected` marker, `lastResult`, the custom `playerMarker` in the map's worldspace, `compassPlayerMarker`, the x and y the HUD compass points at, and `focus`, the x and y the world map camera looks at |
| `state quest <editorID>` | The quest's stage, objectives, and each reference alias with the reference that fills it, or null |
| `state av <name> [--ref <ref>]` | One actor value of an actor (default `player`): base, current, and modifiers |
| `state global <editorID>` | A global variable's value |
| `state scenes` | Each playing scene with its quest, its current phase, and the phase's name |
| `state scripts [<ref or quest editorID>]` | The script queue, the waits, the newest events, the newest fault, and the missing natives. With a reference or quest, also the scripts on it with their state and variables, and the `waits` they are in: the script, the native (`Utility.Wait`, `ObjectReference.PlayAnimationAndWait`), and what wakes it |
| `state packages <ref>` | The actor's package, its procedure, the procedure machine's state and patrol point, the mover's state, and the vehicle links |
| `state furniture [<ref>]` | For an actor (default `player`): its `sitState` (the `GetSitState` value), furniture, marker, entry side, `position`, `sittingRotation`, `leaving` while an exit clip carries it out, and its `idle`: the chosen clip, a failure, its seconds, and `rootMotion`. For a piece of furniture: the record's `rules`, and each marker with its type, whether `MNAM` turns it on, its entry sides, its `position` and floor-level `root`, its holder, and `inUse` |
| `state objects [<ref>]` | Each running object behaviour graph, such as a trap's or a door's: its project, innermost active `state`, every active state in `states`, `waitingForClip` while a clip it reached still loads, and events. With a reference, also `bones`: each bone's `position` in the object's own space and its `rotationDegrees` there, so two reads a few frames apart show a blade swing |
| `state effects [<ref>]` | Each running actor sub-graph: `effect` or `armorAddon`, `actor` (null for an effect at a `point`), `name`, `project`, `state`, `lastEvent`, `eventsTaken`, and `sequences`, the NIF sequences the graph played. With a reference, only that actor's sub-graphs |
| `state nodes [<ref>]` | The placed meshes that play node controllers. With a reference, each driven node with its `position` and `forward` axis in the mesh, `controllers`, `active`, and `frozen` (stopped by bone LOD) |
| `state flight [<ref>]` | Each actor in the air: `phase`, `state` (the `GetFlyingState` value), `feet`, `speed`, `approaching`, `landingPoint`, `landingRequest` (none, hasty, crash), `landingEvent`, `perched`, `perch`, and the forced `order`. The ridden flight adds `rider` (`lockedTarget`, `switchedTarget`, `attacking`). With a reference, that actor only, `getIsFlying` included |
| `state paired` | Each paired animation playing: its `idle`, `event`, `killMove`, and `partnerTookEvent`, and for the `lead` and the `partner` the `ref` and the paired `clips` it played, as prefix, `\|`, and clip |
| `state mount` | The player's mount: `kind`, `phase`, `speed`, `turnRateDegrees`, `stamina` (`current`, `maximum`), `sprintAllowed`, a dragon's `flight`, and the rider's `orders` (`landingRequested`, `lockedTarget`, `switchedTarget`, `attacking`, `breath`) |
| `state favor` | Follower command mode: `phase` (idle, choosing, walking, waiting), `follower`, the walking `task`, `waitLeft` seconds at a spot, `lastDecision` (its `line`, and its `task`, `refusal`, or `crime`), `lastOutcome`, and `pickDistance` |
| `state impulses` | The knockback, explosion push, and splash settings in use, `splashCount`, `waterRings` (the rings on the water now), and the newest `events`: each `knock` (`ref`, `speed`, `knockdown`, `cause`), `push` (`ref`, `impulse`, `cause`), `splash` (`ref`, `weight`, `model`, `position`), or `physicsDamage` (`body`, `ref`, `damage`) ([impulses](/engine/impulses.md)) |
| `state changes [--limit <n>]` | The newest world-state writes, 20 by default (`ref`, `kind`, `reset`), and whether a door transition or an interior rebuild is in flight. A cell that never settles shows the reference that keeps writing |
| `state time` | The game clock, and `sky`: the sun and light directions, the moons, the `moonGlare` colour, the auroras, and the drawn sky objects ([celestial sky](/engine/celestial-sky.md)) |
| `state frame` | The frame counter and the timeline, the `screenFade`, `skippedFrames` (frames not encoded because the GPU was three frames behind), and `gpuMemory`: the device total, the resident render targets, textures, and buffers, the resident count, the retire list, and the streamed textures with their heap memory. `largeReferences` counts the [large references](/engine/distant-lod.md#large-references) drawn with their full model past the loaded grid, and `hiddenLargeReferenceLOD` the object LOD cell segments hidden for them. `fullLODReferences` counts the Is Full LOD references drawn past the loaded grid. `postEffects`: which [screen effects](/rendering/post-effects.md) are on, the `depthOfField` the image space asks for (`strength`, `distance`, `range`, `blurRadius`, `skySharp`, `sides`), and the weather's `volumetricLight` values. `projectileVisuals`: each `flying` projectile's `id`, `model`, whether it is `lit`, and `position`, the muzzle and blast `flashLights` with their `strength`, and the `transientLights` count ([what a projectile shows](/engine/spell-delivery.md#what-a-projectile-shows)). `soundMix`: the mix inputs, the `menuLevel`, `dialogueLevel`, and `musicLevel`, and each category role's `gain` and `paused` ([sound mix](/engine/sound-mix.md)). `treeWind`: the wind `direction` and `speed` the trees use and the `leafFadeDistance` ([trees](/rendering/trees.md)). `waterFlow`: the water `planes` in the scene, the cell `flowMaps` they use, and how many of those `loaded` with their flow noise ([flow maps](/rendering/water.md#flow-maps)) |
| `state view` | What the reference game's console takes: the player's `feet`, the angles, `fovYDegrees`, the cell, `gameHour`, and `weatherFormID` ([reference game](/tools/reference-game.md)) |

## Debug

Debug commands change the game state directly. `state` reads show the result
([where a debug command shows](#where-a-debug-command-shows)).

### World and time

Every teleport ends with the player standing on the ground below the placed spot.

| Command | Does |
| --- | --- |
| `debug teleport --cell <editorID>` | Goes to any cell in the load order, such as `--cell WhiterunBanneredMare` |
| `debug teleport --x <n> --y <n> [--worldspace <editorID>]` | Goes to an exterior cell grid. `--worldspace DLC2SolstheimWorld` goes to another worldspace first |
| `debug teleport --pos x,y,z` | Moves to a position in the current cell or worldspace. Interior positions are local |
| `debug teleport --ref <ref>` | Moves next to a placed object or actor. One outside the loaded cells is found by FormID in any exterior or interior cell |
| `debug view --pos x,y,z --yaw <deg> [--pitch <deg>] [--worldspace <editorID> \| --interior <formID>] [--hour <h>] [--weather <formID>]` | Sets a whole view at once, as `reference follow` sends it. `--pos` is the feet. A `--yaw` of 0 looks east (+X) and turns towards north. A positive `--pitch` looks up. `--hour` is 0 to 24 |
| `debug time <hour>` | Sets the hour, 0 to 24, such as `debug time 13.5` |
| `debug weather [<editorID>]` | Forces a weather. No ID clears the forced weather |
| `debug rest <hours> [--sleep]` | Passes 1 to 24 hours as the wait menu does, or as the rest menu with `--sleep` |
| `debug fasttravel <marker>` | Fast travels to the map marker with this name, such as `Riverwood`, as the map does, without its refusals. The loading screen covers the trip |

### Actors and the player

| Command | Does |
| --- | --- |
| `debug av <name> --value <v>` or `--mod <d>` `[--ref <ref>]` | Sets the base value, as `SetActorValue` does, or adds to the current value, of an actor (default `player`), such as `debug av Health --value 50`. A primary's current value moves with its maximum. Replies `before`, `value`, and `base` |
| `debug item <editorID> [--count <n>] [--ref <ref>] [--equip]` | Adds an item to a container (default `player`), 1 by default. A negative count removes it. `--equip` then equips it on the player |
| `debug perk <editorID> [on\|off]` | Gives the player the perk, or takes it with `off`, as `Actor.AddPerk` does, abilities included. Answers `changed` and `owned` |
| `debug form werewolf\|vampirelord\|none` | Puts the player in a beast form with its race and `SetBeastForm`, without the change scripts, or ends it. Answers `form` |
| `debug kill <ref>`, `debug resurrect <ref>` | Kills or brings back an actor, not the player |
| `debug decapitate <ref>` | Cuts a dead actor's head off, as a severing killing blow does: the body rebuilds with the neck stump and the head falls. Answers `severed` |
| `debug subgraph <ref> --event <name>` or `--var <name> --value <v>` | Sends an event or sets a variable, as `PlaySubGraphAnimation` or `SetSubGraphFloatVariable` does. Answers `taken` and the actor's sub-graphs |
| `debug sound on\|off` | Mutes or unmutes the game's whole sound output. Answers `muted` |
| `debug paired <ref> <target> <idle>` | Plays the `IDLE` with this editor ID on the actor with the target, ignoring its conditions, as `PlayIdleWithTarget` does. A paired idle plays on both ([paired animations](/engine/paired-animations.md)). Answers `chosen`, `failure`, and `pairs` as `state paired` gives them |
| `debug drunk <ref> on\|off` | Raises `DrunkStart` or `DrunkStop` on the actor's graph, as the idles `IdleDrunkStart` and `IdleDrunkStop` do. Answers `taken` |
| `debug knock <ref> <damage>` | Knocks an actor back as a melee hit of `damage` from the player would, without the damage. Answers `knocked`, `speed`, and `knockdown`; a hit below half the current health does not knock |
| `debug eyes <ref> <txst>` | Draws an NPC's eyes with a texture set, as `Actor.SetEyeTexture` does, until its cell unloads |
| `debug link <ref> <node> <other> <othernode> [on\|off]` | Adds or removes the constraint `Game.AddHavokBallAndSocketConstraint` makes, through its script hook. Answers `changed` and `constraints` |
| `debug sit [<ref>] [--furniture <ref>]` | Seats the actor (default `player`) in that furniture, or in the nearest loaded one with a free seat |
| `debug stand [<ref>]` | Gets the actor up from its seat |
| `debug teammate <ref> [--off]` | Sets the player-teammate flag, as `SetPlayerTeammate` does, so a hold of `activate` on the actor opens command mode |
| `debug relationship <ref> <rank>` | Sets the actor's relationship rank toward the player, -4 to 4, as `SetRelationshipRank` does. The reply gives `rank` and `firstFriendRank`, the rank the pair first reached as friends, which fixes how much the player may take from the actor's faction ([crime](/engine/crime.md)) |
| `debug favor <ref> [--target <ref>] [--exit]` | Puts a follower in command mode. `--target` commands it to use that reference, or to go to an `x,y,z` spot. `--exit` leaves command mode |
| `debug flight <ref> takeoff\|land\|perch\|hasty\|crash` | Makes an actor whose race flies take off, land, land on the nearest perch, or make a hasty or crash landing. On the ridden dragon it gives the rider's land order or calls it off |
| `debug quest <editorID> <stage>` | Sets a quest stage |

### Menus and screens

| Command | Does |
| --- | --- |
| `debug racemenu [--limited]` | Opens the race menu, as the console's `ShowRaceMenu` does. `--limited` is `Game.ShowLimitedRaceMenu` |
| `debug skillsmenu [--sky\|--no-sky] [--levelup <n>]` | Opens the skills menu as the Quick Stats key does. `--sky` or `--no-sky` turns the perk sky on or off. `--levelup` first earns 1 to 10 character levels, so the level-up pick shows |
| `debug fade <out\|in> [--white] [--delay <s>] [--duration <s>]` | Fades the screen to black, or to white with `--white`, as `Game.FadeOutGame` does |
| `debug cartmode on\|off` | Puts the HUD into or out of cart mode, as `Game.SetHudCartMode` does |
| `debug loadscreen [<id>]` | Holds the `LSCR` screen with this editor ID on screen. No ID releases it and starts its fade |
| `debug playbink <file> [--interruptible]` | Plays a Bink movie from `Data\Video`, such as `BGS_Logo.bik`, as `Game.PlayBink` does. `--interruptible` lets a key skip it |
| `debug skipbink` | Ends the playing movie, even one a key cannot skip |
| `debug titles <step>` | `show` or `hide` the opening titles of `interface\titles.swf`, or plays one clip such as `Sequence1`, through the `MQ101` script hooks |
| `debug gamepad [--count n] [--press down,a]` | Reports `n` gamepads (0 to 3) to the menu movies when fewer are connected, and presses gamepad buttons (`a`, `b`, `x`, `y`, `up`, `down`, `left`, `right`) on the next frame |

### Rendering

| Command | Does |
| --- | --- |
| `debug overlay <layer> on\|off` | Turns a debug overlay (`navmesh`, `path`, `detection`, `hud`, `ui`) or a render layer (`statics`, `actors`, `distantlod`, `terrain`, `grass`, `water`, `sky`, `particles`) on or off |
| `debug channel <mode>` | Shows one debug channel of the scene pass: `off`, `wireframe`, `worldnormals`, `texturecoordinates`, `miplevel`, `shadowcascade`, `layercategory` |
| `debug shadows <off\|low\|high>` | Sets the sun shadow tier until the renderer is rebuilt; `shadowLights` reads how many point lights drew a cube shadow last frame |

### Where a debug command shows

| Command | Read it back with |
| --- | --- |
| `debug skillsmenu --levelup` | `state player` `level`. A frozen leveled roll keeps its level until its cell resets (`debug rest 240` away from it) |
| `debug link` | `state actors` `constraints` |
| `debug relationship` | `state target` `theft` on an item of the actor's faction |
| `debug eyes` | `state actors` `eyeTexture` |
| `debug decapitate` | `state actors` `severed` |
| `debug fade` | `state frame` `screenFade` |
| `debug cartmode` | `state menu` `hud.cartMode` and `hud.modes` |
| `debug loadscreen` | `state menu` `loading` |
| `debug playbink` | `state menu` `bink.frame` and `bink.lastOutcome` |
| `debug titles` | `state menu` `titles` |
| `debug gamepad` | `state menu` `movie.focus`, `movie.focusLabel`, `movie.controllers`, and `movie.platform` |

## Benchmark

| Command | Does |
| --- | --- |
| `benchmark [quick\|standard\|full] [--scenes a,b] [--set id=v,id=v] [--no-overlay] [--no-load-passes] [--screenshots] [--windowed\|--full-screen] [--size WxH] [--sound] [--capture <id>] [--out <absolute dir>]` | Flies the benchmark tour, hidden and muted by default, and replies when it ends, with the result folder, `comparable`, `stopped`, the failed scenes, and the summary |
| `benchmark --stop` | Stops a running tour. The scenes measured so far are kept |

The tour takes over the camera, the clock, and the HUD until it ends
([benchmark](/tools/benchmark.md)).

## Events

| Command | Does |
| --- | --- |
| `events [--filter a,b] [--since <seq>]` | Lists the ring buffer of recent events |
| `events --follow [--filter a,b] [--since <seq>] [--timeout <s>]` | Streams events as they happen. `--filter` keeps only those kinds, and `--since` only events after that sequence number |
| `events --until <kind> --timeout <s>` | Waits for the first event of that kind after the call |

| Event kind | Fires when |
| --- | --- |
| `cell.loaded`, `cell.unloaded` | A cell finishes loading or unloads |
| `activation`, `activation.refused` | The player uses a reference, or the game refuses it |
| `menu.opened`, `menu.closed` | A menu opens or closes |
| `combat.hit` | A hit lands |
| `actor.death` | An actor dies |
| `quest.stage` | A quest stage is set |
| `script.error` | A Papyrus script faults |
| `log` | The engine writes a log line; the event carries its `category` and `message` |
| `time.paused`, `time.resumed` | The clock stops or starts |

## Scripts

A script is a JSONL file: one JSON object per line. A line that starts with `#` is a comment.

```text
{"command": "time.pause"}
{"command": "debug.av", "args": {"name": "Health", "value": 50}}
{"command": "state.av", "args": {"ref": "player", "name": "Health"}, "expect": {"value": 50}}
```

| Key | Means |
| --- | --- |
| `command` | The command, with a dot between its words |
| `args` | The arguments. `--record <file>` on any call writes the exact keys |
| `expect` | Dotted paths into `result` and the value each must have. Numbers match within 0.0001 |

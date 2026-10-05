---
type: Tool
title: Agent control
description: How openskycli game drives the running app - the control socket, the line
  protocol, deterministic stepping, the shared input path, and a worked session.
tags: [tool, cli, agent, testing]
---

# Agent control

Agent control lets a script or an agent play the running app from a terminal. The app runs a
small server, and `openskycli game ...` sends it one command per call. The workflow for agents
is in the `driving-the-running-game` skill; this page explains how the parts fit.

## The server

The server is off by default. Two things turn it on:

- `openskycli game launch`, which opens the app with `OPENSKY_AGENT_CONTROL=1`.
- Developer > Agent Control > Agent control server, in the sidebar.

It listens on a Unix domain socket, never a network port. The default path is
`~/Library/Application Support/OpenSky/agent-control.sock`; `OPENSKY_AGENT_SOCKET` changes it
for both the app and the CLI. The folder is created with mode 0700 and the socket with mode
0600, so only the user's own processes can connect. A stale socket file from a crashed app is
removed at start; a live one is an error, so two apps never share a path.

The app polls the socket on the main actor from a run-loop timer. Every command therefore
runs between two frames, on the same actor as the game, with no locks.

## Wire format

Newline-delimited JSON. Each line is one object; a line over 64 KiB is refused.

1. On connect, the app sends a hello:
   `{"app":"OpenSky","appVersion":"...","dataRoot":"...","protocolVersion":1,"worldReady":true}`.
   The CLI stops with `versionMismatch` when `protocolVersion` differs from its own.
2. The client sends a request: `{"id":1,"command":"state.player","args":{}}`.
3. A waiting command may send stream lines first: `{"id":1,"event":{...}}`.
4. The reply ends the request:
   `{"id":1,"ok":true,"frame":812,"paused":true,"eventSeq":40,"result":{...}}`, or
   `"ok":false` with `"error":{"code":"notFound","message":"..."}`.

A connection runs one request at a time, in order. Error codes: `malformedRequest`,
`unknownCommand`, `invalidArgument`, `notReady`, `notFound`, `unsupported`, `timeout`,
`versionMismatch`, `notRunning`, `failed`.

The CLI turns words into a request: `game input hold forward --frames 60` becomes
`{"command":"input.hold","args":{"action":"forward","frames":60}}`. Kebab options become
camelCase keys, and words that read as numbers or `true`, `false`, `on`, `off` are typed.

## Pause and step

Every simulation clock in the renderer reads one wall clock. The app gives the renderer a
`SteppedWallClock`, so freezing that one clock freezes movement, animation, physics, scripts,
and game time together, while the window keeps drawing. A step adds exactly one fixed
interval (1/60 s by default) to the clock in the next drawn frame. So a paused run that sends
the same commands gets the same frame deltas on any machine, however fast it draws.

A key press made while paused is kept until the next step, because a frame with no elapsed
time does not consume one-shot input. A screenshot renders with the simulation paused, so
taking one does not move the game.

A step only advances when a frame draws. A minimized or hidden window draws nothing, and a
step then ends in `timeout`.

## The same input path as the keyboard

`input` commands name logical actions, such as `forward` or `activate`. The keyboard and the
agent both go through one dispatcher: in the world an action reaches the camera input; while a
menu owns input, movement becomes menu navigation and other actions are swallowed. So an
injected press does exactly what the key does. `input select <label>` moves the open menu's
selection with the same up and down events, one row at a time.

## Events

The app keeps the last 512 events in a ring buffer. Each has a sequence number that only
grows. Cell loads and unloads and activations come from streamer callbacks. Menus, deaths,
quest stages, melee hits, and script faults are found by comparing state between polls, so they
can arrive a few frames after the cause. Error and fault lines from the app's own loggers come
from an in-process buffer that `EngineLogger` fills. Querying the system log store instead kept
one core busy the whole time.

`events --until <kind>` waits for the first event of that kind after the request. A plain
`events` lists the ring.

## Limits

- References are named as `player`, `target` (the crosshair), or a hex FormID of a loaded
  reference. There is no editor-ID index for placed references.
- `debug teleport --pos` and `--ref` stay in the current cell, because interior positions are
  local to their cell. `--x --y` and `--cell` change cells.
- `debug teleport --cell` searches Skyrim.esm only. An interior is entered through one of its
  doors, so the player arrives at that door's marker.
- `debug resurrect` clears the death record and refills the actor values; the ragdoll keeps
  its pose until the cell reloads.
- Items can only be added to or removed from the player.

## Worked example

This session pauses, walks one second, and checks a quest stage and an actor value.

```text
$ openskycli game launch
{"dataRoot":"/Volumes/data/steam/steamapps/common/Skyrim Special Edition/Data","mode":"play",...,"worldReady":true}
$ openskycli game time pause
{"eventSeq":3,"frame":420,"id":1,"ok":true,"paused":true,"result":{"frame":420,"paused":true,...}}
$ openskycli game input hold forward --frames 60
{"eventSeq":3,"frame":481,"id":1,"ok":true,"paused":true,"result":{"action":"forward","released":true}}
$ openskycli game debug av Health --value 50 --text
before: 100
name: Health
ref: 00000014
value: 50
$ openskycli game debug quest DA16 10 --text
completed: false
id: DA16
running: true
stage: 10
$ openskycli game screenshot
{...,"result":{"height":720,"path":".../logs/game-screenshot/20261003T180000/screenshot.png",...}}
```

The same checks as a replayable script, run with `openskycli game run check.jsonl`:

```text
{"command": "time.pause"}
{"command": "input.hold", "args": {"action": "forward", "frames": 60}}
{"command": "debug.av", "args": {"name": "Health", "value": 50}}
{"command": "state.av", "args": {"ref": "player", "name": "Health"}, "expect": {"value": 50}}
```

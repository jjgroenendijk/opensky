---
name: driving-the-running-game
description: Drives the live OpenSky app from the terminal with openskycli game - launch,
  pause and step frames, press or hold input, read player, target, menu, quest and actor
  state, teleport, change actor values or items, wait for events, take screenshots, and
  replay JSONL scripts. Use when a task asks to play, walk, test, or debug something in the
  running game window, or when openskycli game reports notRunning.
---

# Driving the running game

`openskycli game ...` talks to the running app over a local Unix socket. Each call prints
one JSON object, and the reply carries `ok`, `frame`, `paused`, and `result` or `error`.
The command list and every argument are in [reference.md](reference.md). The protocol is
in `docs/tools/agent-control.md`.

Build first with `make build-app` and `make build-cli` (background shell, root `AGENTS.md`).
Run the CLI as `"$(make -s app-path | xargs dirname)/openskycli" game ...` or through
`make run-cli ARGS="game ..."`.

## Workflow

1. Tell the user a game window will open, then start it:
   `openskycli game launch` (play mode) or `game launch --mode developer`. It waits until
   the world is loaded. The app opens a real window on the user's screen.
2. Pause before you act: `game time pause`. A paused game only moves when you step it, so
   every result is the same on every run. Running time depends on the machine.
3. Act in frames, not in shell sleeps: `game input hold forward --frames 60` steps 60
   frames of 1/60 s while forward is held. `game time step 10` steps without input.
4. Wait for game events instead of guessing a delay:
   `game events --until cell.loaded --timeout 30`.
5. Check with state reads: `game state player`, `state target`, `state menu`,
   `state quest <id>`, `state av <name>`.
6. Look with `game screenshot`. It writes to `.logs/game-screenshot/<UTC>/` by default.
   A capture shows game assets, so it stays in `.logs/` and never lands in a commit
   (root `AGENTS.md`, Legal & IP boundary).
7. End with `game quit`, unless the user wants the window kept.

For a check that must repeat, write a JSONL script with `expect` objects and run it with
`game run <file>`; it stops at the first failed line. `--record <file>` on any call
appends that call to a script, so record a run first to see the exact `args` keys. Keep
scripts in `.logs/`: they need the user's install, so no tracked suite runs them.

## When it fails

- `notRunning`: the server is off by default. `game launch` turns it on, or the user
  ticks Developer > Agent Control > Agent control server in the sidebar. There is no
  network port.
- `versionMismatch`: the app and the CLI come from different builds. Rebuild both.
- `notReady`: the world is still loading or a door is opening. Wait with
  `events --until cell.loaded`, then retry.
- `timeout` on `time step`: the window is hidden or minimized, so no frame draws. Ask
  the user to keep it visible.
- A wrong answer from the game is a bug in OpenSky, not in the script. File it with the
  `bug` label (root `AGENTS.md`).

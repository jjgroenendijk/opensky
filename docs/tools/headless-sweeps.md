---
type: Tool
title: Headless sweeps
description: How `openskycli sweep` starts every quest, runs every script fragment, and checks the
  rules vanilla data implies, without a window, and how to read the fallback counts each run writes.
tags: [tool, cli, coverage, scripting, quests]
---

# Headless sweeps

A headless run uses the engine with no window and no loaded cell. The `sweep` commands use one
to try the whole game at once. Each finds what fails and ranks it, so the top rows are the
problems that stop the most content.

```sh
make build-cli CONFIG=Release
.build/.../openskycli sweep quests
.build/.../openskycli sweep fragments --limit 30
.build/.../openskycli sweep rules --examples 5
```

`make help` prints where the Release `openskycli` is. Each run writes `report.txt`, and the
quest and fragment sweeps also write `fallbacks.tsv`. They go to
`.logs/sweep-<kind>/<UTC time>/`, or to `--out`. The files hold editor IDs, FormIDs, script
names, and counts only, no game content.

All three share these options:

| Option | Meaning |
| --- | --- |
| `--out <directory>` | Write the files here instead of the run directory |
| `--limit <n>` | Print only the top `n` problems; the file keeps all |
| `--examples <n>` | Name `n` subjects per problem (default 3) |

## The engine the sweeps run on

The sweeps build the same quest and Papyrus layers as the app, over the whole load order:

- the quest store and runtime, with the persistent references as the only search space;
- the Papyrus VM with the standard natives and the install's own compiled scripts;
- the load-order FormID space, so every record resolves as it does in the app.
- the load order's global variables, and a clock that stands at a new game's start.

There is no loaded cell, no actor body, no player position, and no menu, and game time
never passes. A native that
needs one of these answers its default. So a problem in a report is either a gap or a seam
the headless engine does not fill. The fallback names tell them apart.

## Quest sweep

`sweep quests` starts each quest that the game starts on its own: those flagged "Start Game
Enabled", and those a story-manager quest node can start. The start is the one a script
`Start()` makes: fill the aliases, attach the scripts, set the start-up stage, and run the
queued script events until the queue is empty. Each sweep steps the queue at most 64 fixed
steps per subject, then drops the calls still waiting, so one subject's wait loop does not run
into the next.

| Problem | When |
| --- | --- |
| `alias does not fill (<fill type>)` | A required alias stays empty, so the quest does not start |
| `first stage not reached` | The quest started, but its start-up stage is not done |
| `first stage not reached (started earlier by a script)` | The same, for a quest another quest's script had already started |
| `stage fragment error: runtime error: <name>` | A fragment faulted, or a native in it failed |
| `scene cannot start: actor alias empty` | A "Begin on Quest Start" scene has a required actor alias with no one in it |
| `start fails: <error>` | The quest layer refused the start |

A `from event` alias can never fill here, because no story event starts the quest. Those
rows count quests that need the event, not broken quests.

## Fragment sweep

`sweep fragments` runs every script fragment alone: each quest stage's fragments, each topic
info's begin and end fragments, each scene fragment and phase fragment, and each package
fragment. It reads the fallback counts before and after each run, and each count that rose
is a problem of that fragment.

How a fragment gets its context:

- A quest stage fragment runs on the quest's own script, attached with its aliases filled as
  far as the search can fill them. The quest does not need to run.
- A topic info fragment gets its topic's quest as the owning quest and no speaker.
- A scene fragment gets its scene's quest as the owning quest.
- A package fragment gets the player as its actor.

| Problem | Fallback behind it |
| --- | --- |
| `native returns None: <script.function>` | A native answered None where its signature promises a value |
| `property does not resolve: <reason>` | A script property bound to nothing |
| `native does nothing yet: <script.function>` | A native is not bound, or answers a stub |
| `runtime error: <name>` | The VM faulted, or a native failed with a reason |
| `script does not attach: <reason>` | The fragment's script did not attach. A script with no handler for an event, and a script the record marks removed, are skipped by the game too, so they are not problems |
| `fragment does not queue` | No instance took the fragment |
| `script queue still busy after the drain` | The fragment still ran after 64 fixed steps, such as a loop around `Utility.Wait` |

What the run cannot see: a fragment's effect on the world, a fragment that waits for game
time, and a branch the default answers never take. A native that answers None because the
headless engine has no actor or cell shows up as `native returns None`, the same as a gap.

## Rule sweep

`sweep rules` checks facts vanilla data must hold for the game to work. Each rule states why.
A violation names the rule and the record. The rules live in `SweepRulesCommand.rules`.

| Rule | What it checks | Why vanilla data must satisfy it |
| --- | --- | --- |
| `npc-package` | Each placed unique NPC has a package that resolves and whose hour is -1 to 23: its own, from its template, from its default list, or from a quest alias | A placed unique NPC stands in the world all day, so a package runs it |
| `load-door-navmesh` | The cell at the far side of each load door has a navmesh | The player and followers arrive there and walk on |
| `leveled-list` | Every entry names a record that exists | The game rolls the list to place an item, an actor, or a spell; an empty list is allowed, because vanilla rolls some to give nothing |
| `topic-info` | A topic with infos has one that does not ask one condition for two answers | A topic is said through an info whose conditions can pass; a topic with no info is never said |
| `placed-base` | Each placed reference's base exists and is a type the engine builds | Every placed reference shows its base |

What the rules cannot see: a condition that depends on game state, a package whose conditions
never pass, and a navmesh that does not reach the door. The condition check only judges a list
with no OR, and only two `==` or `==` and `!=` tests of one function with the same parameters.

To add a rule:

1. Add a `Rule` to `SweepRulesCommand.rules` with an id, the reason, and the check.
2. Read what the check needs in `SweepRuleData`, which walks every plugin once.
3. Put any logic beyond a lookup in `VanillaDataRules`, with a unit test.
4. Add the row to the table above.

## Fallback counts

A fallback is a place where the engine meets something it does not handle and goes on with a
default. Each fallback counts under a stable name, so two runs compare line by line.
`fallbacks.tsv` holds one `name<TAB>count` line per name, most counted first.

| Name | Meaning |
| --- | --- |
| `unimplemented native <script.function>` | No handler is bound |
| `stubbed native <script.function>` | The handler answers a stub that does not match the game |
| `deferred animation <script.function>` | The handler skips an animation it cannot play yet |
| `failed native <script.function>: <reason>` | The handler refused its arguments; digits read `#` |
| `None from native <script.function>` | The handler answered None for a typed return |
| `fault <kind>` | The VM stopped a function, such as `missingFunction` |
| `call on a None receiver` | A script called a method on None |
| `script skip <reason>` | An event or attach was skipped |
| `property binding skip <reason>` | A property bound to nothing |

Compare two runs with `diff` on the two files. A name that drops is work that landed. A new
name is a new fallback.

A handler that does no work and is not named this way cannot be counted. The gate
`tools/lint/syntax-rules.sh` stops one from being added: `unnamed_native_stub` and
`unnamed_condition_stub` fail a handler that only answers a constant, unless it answers
`.deviated(_, .stubbed)`, a `.failure(...)` with a reason, or carries a `// Matches the game:`
comment that says why the game does nothing there either ([gap report](/tools/gaps.md),
"Shallow handlers").

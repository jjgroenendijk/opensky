---
type: Subsystem
title: GameDelegate bridge
description: How a movie calls the engine and the engine calls a movie through Scaleform's
  GameDelegate, how a response ID is told apart from an argument, the invoke log, and what driving
  the vanilla menus showed.
tags: [engine, swf, actionscript, ui, scaleform]
---

# GameDelegate bridge

`gfx.io.GameDelegate` is Scaleform's channel to the host, and vanilla uses it: 1,520 references
across 38 of the 53 movies. OpenSky uses its shape instead of inventing a bridge, because the movies
are not modified and a different bridge would mean they call into nothing. The interpreter is on the
[AS2 runtime](/engine/as2-runtime.md) page.

The delegate is ActionScript shipped inside each movie. In `startmenu.swf`,
`_global.gfx.io.GameDelegate` has `call`, `receiveResponse`, `addCallBack`, `removeCallBack`,
`receiveCall`, `initialize`, `responseHash`, `callBackHash`, and `nextID`. So the engine does not
rebuild it. It supplies the two ends the delegate reaches for.

## Movie to engine

`ExternalInterface.call` and `fscommand` are player built-ins, so the engine provides them, and
`GameDelegate.call` goes through the first. A registered Swift handler answers. An unregistered name
is a logged no-op and a tally entry, the rule the [AS2 scope decision](/decisions/swf-as2-scope.md)
set. `ExternalInterface` is installed both as a bare global and as
`flash.external.ExternalInterface`, because AS2 spells it both ways.

A response ID cannot be told from an ordinary argument by its shape, and guessing fails for real:
`tweenmenu.swf` calls `HighlightMenu(3)`, where 3 is the only argument, and a rule that treated any
first number as an ID would drop it. The delegate's own bookkeeping decides instead. It writes
`responseHash[id]` just before the call when the movie passed a callback, and passes -1 when it did
not. So an ID is a number that is either -1 or a live `responseHash` key, and only a movie with a
delegate can make either. A handler's value goes back through `GameDelegate.receiveResponse(id,
value)`.

## Engine to movie

The engine calls a callback the movie registered with `addCallBack`, through `receiveCall`. A movie
with no delegate falls back to a function on the root clip, so the engine has one entry point either
way. A name neither answers is a tally entry and an unhandled log entry.

Some movies put their host entry points on a named instance instead. `hudmenu.swf` has its HUD
functions on `/HUDMovieBaseInstance`. A call can name that path: the instance is found, and the
function runs with it as `this`. A missing path is a counted miss and an unhandled call, not a crash.

## The invoke log

Both directions go into one log. Each entry has the direction, name, arguments, result, and whether
it was handled. At most 256 entries are kept, oldest dropped first, and the totals (all, unhandled,
dropped) keep counting. Each argument summary is cut to 240 characters. An object is summarized by
its kind, not walked, because the log must not depend on an object graph that may have cycles.

## What the vanilla movies showed

`openskycli swf action-run` brings one movie up, ticks it, and prints faults, missing names,
registered classes, callbacks, the invoke log, and the display tree. `--dump-class` prints a
registered class's constructor and prototype, and `--dump-proto` walks a node's whole prototype chain
([CLI](/tools/cli.md)). All 53 vanilla movies bring up and tick with no fault and no unimplemented
opcode, and register 305 classes.

The names still missing are mostly CLIK component state, headed by `_listeners`,
`invalidationIntervalID`, `textField`, `height`, `width`, `CLIK_loadCallback`, `focusIndicator`, and
`inspectableGroupName`. Menu data is published only where a feature needs it.

### tweenmenu.swf

Skyrim's four-way pause selector (Skills, Magic, Inventory, Map). Its options are clips in the movie,
not data from the engine. Its class `TweenMenuObj` has `StartOpenMenuAnim`, `onFinishOpenMenuAnim`,
`handleInput`, `onInputRectMouseOver`, `onInputRectClick`, `StartCloseMenuAnim`, and
`onCloseComplete`. Opening it takes `SetPlatform`, `InitExtensions`, and `StartOpenMenuAnim`. Arrow
keys and the pointer each move the selection and call `HighlightMenu(n)`. Opening calls
`OpenAnimFinished()` and closing calls `CloseMenu()`. Every call is handled. The misses left are the
gamepad focus path (`getControllerFocusGroup`, `findFocus`, `getControllerMaskByFocusGroup`) and
one-shot `_global` guard reads (`gfx`, `Shared`, `Components`).

### startmenu.swf

This is Skyrim's title screen, not the in-game system menu. Its 1,674-string pool has no
`$SETTINGS`, and its rows are Continue, New, Load, Creations, Mods, Credits, Quit, and Help. The
in-game system menu is `quest_journal.swf`, whose pool has `$SYSTEM`, `$SETTINGS`, `$CONTROLS`,
`$SAVE`, `$LOAD`, `$QUIT`, and the settings tree ([system menu](/engine/system-menu.md)).

`_root.CodeObj` is not a host object, though the bytecode only calls through it. The movie makes it
itself: `StartMenu`'s constructor runs `_root.CodeObj = this.codeObj = new Object()` and installs
`_root.ReleaseCodeObject` and `_root.onCodeObjectInit`. All 16 names reached on it are outbound calls
on the Bethesda.net login path (`initLogin`, `BeginLogin`, `GetBnetUpdate`, `ModsBlockedByBnet`,
`CClubBlockedByPermissions`, `CClubBlockedByBnet`, `startEditText`, `endEditText`,
`onLoginScreenOpen`, `onLoginScreenClose`, `attemptLogin`, `createQuickAccount`, `AcceptLegalDoc`,
`PopulateEULA`, `PlaySound`, `PlayOKSound`). No-op natives answer them, and the login screen never
opens.

The list is filled by three calls in order: `SetPlatform(0, false)` and `InitExtensions` on
`/MenuHolder/Menu_mc`, then the delegate callback `sendMenuProperties` with 14 flat arguments.
`InitExtensions` registers that callback: the movie goes from 4 callbacks to 17. `setupMainMenu`
then clears `MainList.EntriesA`, pushes one `{text, index, disabled, showIcon}` row per enabled
entry, and calls `InvalidateData()`. OpenSky answers with no saves, so the list has no `$CONTINUE`
and `$LOAD` is disabled.

The outbound side needs six names: `myLog`, `PlaySound`, `PlayOKSound`, `StartState`, and
`currentState` as delegate functions, and `gfxProcessSound` as a plain `_global` native. `myLog`
alone is called 24 times, all from the movie's own `DoInitAction` blocks. That is why the host can
register functions before bring-up.

### inventorymenu.swf

The movie brings up with no fault, but it places three characters it never defines. Until
characters could be imported from other movies ([SWF container](/formats/swf.md)), the whole list
subtree created nothing and the movie had 11 nodes. With imports it has 373 nodes and 16 classes.
`UpdateItem3D` and `EndItem3D` are answered as no-ops, because the rotating item preview is not done.
`InventoryDefines` is not read: the menu groups items by OpenSky's record families
([inventory menu](/engine/inventory-menu.md)).

### quest_journal.swf

An AS2 class keeps its methods on a prototype, and a widget gets most of its contract from a base
class the movie never registers. No node dump reaches either, which is why the two dump options
exist. They show `QuestsPage`'s 30 methods, `QuestJournalBase`'s `PAGE_QUEST`, `PAGE_STATS`, and
`PAGE_SYSTEM` constants, and the shared list base with `EntriesA`, `entryList`, `iSelectedIndex`,
`InvalidateData`, `ClearList`, and `SetEntry`.

Two details were found by driving it:

- `InvalidateData` rebuilds only as many entry clips as there are rows, and leaves the rest showing
  the previous rows. An emptied list needs `ClearList`, which hides the extra clips.
- An objective row's state is plain `completed` and `failed` booleans. Setting them moves the entry
  clip from its `Normal` frame to `Completed` or `Failed`.

Two missing names change the picture: with no `textField` on an entry clip, the clip cannot draw its
row's text, and with no `height`, a text field keeps its authored size, so a long journal paragraph
overlaps the objective list below it ([journal](/engine/journal.md)).

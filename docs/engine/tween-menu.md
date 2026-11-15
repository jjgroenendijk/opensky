---
type: Subsystem
title: Tween menu
description: The menu the Tween Menu key opens over the paused world, its four entries, and
  the calls of its movie.
tags: [engine, menu]
---

# Tween menu

The Tween Menu key (Tab) opens the Tween menu over the paused world. It has four entries:
Skills at the top, Magic on the left, Items on the right, and Map at the bottom. Choosing an
entry shuts the Tween menu and opens that menu, as its own key does: the
[skills menu](/engine/skills-menu.md), the magic menu, the
[inventory menu](/engine/inventory-menu.md), or the map. Tab or Esc shuts it again. In
follower command mode, Tab only leaves that mode ([follower commands](/engine/follower-commands.md)).

A bar along the bottom shows the date line, the player's level, and how far the player is
toward the next level. While a level waits to be applied, the Skills entry reads "LEVEL UP".

`openskycli game input press tweenMenu` opens the menu as Tab does, and `state menu` reads
`tween`: the highlighted entry, `levelUp`, and whether the close animation runs.

## The movie

`Interface\tweenmenu.swf` owns the four entries, their highlight, the arrow keys, the mouse,
and the open and close animations. Read from the movie's compiled actions in the install, the
engine calls the root `InitExtensions` and then these `GameDelegate` callbacks:

| Call | Arguments |
| --- | --- |
| `ShowMenu` | none; shows the menu and the bottom bar |
| `StartOpenMenuAnim` | whether a level waits, the date line, the level as text, the level progress from 0 to 100 |
| `StartCloseMenuAnim` | none; plays the close animation |

The movie calls the engine back:

| Call | When |
| --- | --- |
| `HighlightMenu(n)` | the arrow keys or the mouse move the highlight |
| `OpenHighlightedMenu(n)` | Enter or a click chooses an entry |
| `OpenAnimFinished` | the open animation ends |
| `StartCloseMenu` | Tab starts the close animation |
| `CloseMenu` | the close animation ends |

The entry number `n` is 1 for Skills, 2 for Magic, 3 for Items, and 4 for Map. The movie
also has `HideMenu` and `ResetStatsButton`; OpenSky does not call them.

Esc reaches the engine, not the movie. OpenSky answers it as the movie answers Tab: it plays
the close animation and shuts the menu when the movie calls `CloseMenu`.

Without the movie, OpenSky draws a text panel: the arrow keys pick the entry that sits that
way, and Enter opens it.

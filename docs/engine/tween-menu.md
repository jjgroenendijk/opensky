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

## Camera

While the menu is open, the camera widens its view and turns a little toward the
highlighted entry. A clean-room read of `SkyrimSE.exe`, 2026-11-15, found:

- On open, the horizontal field of view grows by 10 degrees at a fixed 25 degrees a second,
  so it takes 0.4 seconds.
- A highlighted entry sets a turn target of 0.05 radians (about 2.9 degrees). Each frame the
  turn moves a share of the gap to its target: 4 times the frame time while open, 10 times
  while closing. A share of 1 or more lands on the target.
- On close, the turn and the field of view go back to 0 at the same rates. The move ends
  when the field of view is back, so it can end after the menu has shut.
- The camera does not move closer to the player.

The read did not say which entry turns which way. OpenSky turns toward where the entry sits:
up for Skills, left for Magic, right for Items, and down for Map
([unverified values](/engine/unverified-values.md)).

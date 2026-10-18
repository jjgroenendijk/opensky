---
type: Subsystem
title: Books
description: How a carried book or note opens in the book menu, and what reading it
  teaches.
tags: [engine, menu, inventory]
---

# Books

Using a book or a note in the inventory closes the inventory and opens the book menu on its
text. Activating a book that lies in the world opens it too, without picking it up. The text
is the `BOOK` record's `DESC`, from the `.dlstrings` table
([localized strings](/formats/strings.md)). A record with the note flag opens as a note.

## Reading

Reading takes effect when the book opens, as in the game:

- A skill book raises its skill once ([skill books](/engine/skill-advancement.md)).
- A spell tome teaches its spell ([spellcasting](/engine/spellcasting.md)).

## The movie

`Interface\book.swf` lays the text out on pages itself. `BookMenu.onLoad` registers three
callbacks:

| Call | What it does |
| --- | --- |
| `SetBookText(text, isNote)` | Loads the text, with the game's HTML tags |
| `TurnPage(delta)` | Turns the pages. OpenSky sends 2 for a book and 1 for a note |
| `PrepForClose` | Lets the movie end its page animation |

Left and right arrows turn the pages, and Escape closes the book.

## The button bar

`Interface\bookmenu.swf` is the bar under the pages, drawn as the
[overlay movie](/rendering/swf-layer.md#overlay-movie). Its frame script calls
`BottomBar.InitExtensions`, which registers one callback, measured on the install:

| Call | What it does |
| --- | --- |
| `InitExtensions(platform, swapPS3)` | A root function: sets the button art |
| `ShowTakeButton(show, steal)` | Shows the take button, labelled `$Take`, or `$Steal` when `steal` is true |

For a book in the inventory the take button is hidden. For a book read where it lies it shows,
and Enter or E takes the book and closes the menu. Taking a book that someone owns is theft, by the
same rule as taking any item ([crime](/engine/crime.md)).

## Differences from the game

- Which key takes the book in the game is not checked. OpenSky uses the accept key.
- The game draws the book as a 3D model with the movie on its pages. OpenSky draws the
  movie flat.

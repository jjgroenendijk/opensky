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

## The 3D book

In the game the book is a 3D model with the movie drawn on its pages:

- The model sits at 0.5 of the screen width and 0.445 of its height, turned -25 degrees about the
  X axis. Its distance is 110 for a book and 90 for a note, times the screen width over its height.
  It moves, turns, and scales from its start to that place over 1 s.
- Two lights of colour (0.98, 0.95, 0.83) and radius 400 light it: one at (100, -350, 100) with
  dimmer 1.75, one at (10, -75, 10) with dimmer 1.
- The pages are the model's nodes `Base Page1` to `Base Page4`. A model without `Base Page1` opens
  as a note. For each page the engine calls `BookMenu.BookMenuInstance.ShowPageAtOffset(i)` and
  draws the movie onto that node.
- The movie splits the text into pages and keeps the first and last page; the engine does not.

```mermaid
flowchart TD
    Key[Back or forward input] --> Flip{Page flip running?}
    Flip -->|yes| Ignore[Ignore the input]
    Flip -->|no| Turn["TurnPage(±2 for a book, ±1 for a note)"]
    Turn --> Moved{Did the movie turn the page?}
    Moved -->|no| Stay[Nothing more]
    Moved -->|yes| Anim[Play the page animation on the model]
    Anim --> Note{A note?}
    Note -->|yes| Sound[Play ITMNotePageTurn]
```

Back is `PrevPage`, `LeftEquip`, or left; forward is `NextPage`, `RightEquip`, or right. A note
also takes up for back and down for forward. Accept takes a book that lies in the world and closes
the menu; Cancel closes it. Neither works during a page flip. On close the engine calls
`PrepForClose`, then moves the book back over the same open time.

A skill book teaches once, when its skill is one of the 18. The gain is 1 level, changed by the
`Adjust Book Skill Points` perk entry point, rounded down, at least 1. A skill at 100 gains
nothing, but the book is still used up.

A spell tome read from the inventory teaches its spell without opening the book menu. A new spell
plays `UISpellLearned`, shows the spell-added notice, and uses up one tome. A known spell shows the
already-known notice, plays no sound, and keeps the tome. A tome read from a container is removed
only for a new spell. The first read of any book marks it read and counts it for the stats
([general stats](/engine/statistics.md)).

## Differences from the game

- The `BOOK` record has a "Can't Be Taken" flag. The
  [CK wiki](https://ck.uesp.net/wiki/Book) marks it "Does not work?", so OpenSky ignores it
  until a test in the game shows what it does.
- The game draws the book as a 3D model with the movie on its pages
  ([3D book](#the-3d-book)). OpenSky draws the movie flat.

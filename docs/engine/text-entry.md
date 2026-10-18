---
type: Subsystem
title: Text entry
description: The one-line name field of `Interface\textentry.swf`, how typed keys reach
  it, and how its result comes back.
tags: [engine, menu, input]
---

# Text entry

The text entry screen is a one-line field with Accept and Cancel buttons. OpenSky opens it
from the sidebar (HUD & Interaction > Menu screens, "Text entry"). No source names the game
action that opens it, so no game action opens it in OpenSky yet.

## The movie

`Interface\textentry.swf` places nothing on its stage. It exports one symbol,
`TextEntryClip`, with the class `TextEntryField`. The engine builds the field itself, as
measured on the install:

1. `_root.attachMovie("TextEntryClip", "TextEntry_mc", 1)` places the field.
2. `SetupButtons()` makes a click on each button call `onAccept` or `onCancel`.
3. `SetPlatform(platform, swapPS3)` picks the button art.
4. `addEventListener("nameChange", scope, callBack)` listens for the result.

`TextField_txt` names the child `TextInputInstance`, a CLIK `TextInput`. The engine writes
the typed text to its `text` property.

The movie sends one event:

| Button | Event |
| --- | --- |
| Accept | `{type: "nameChange", nameChanged: true}`, only when the text is not empty (`GetValidName`) |
| Cancel | `{type: "nameChange", nameChanged: false}` |

## Input

The movie's own `TextInput` does not take keys in OpenSky. The game view sends typed
characters to the screen instead, the same way the race menu takes a name:

- A character key adds its character, up to 64.
- Delete and Backspace remove the last character.
- Enter calls the movie's `onAccept`, and Escape calls `onCancel`, so the movie's own rule
  for an empty name holds.

Without the movie, a text panel shows the field. Enter accepts a text that is not empty.

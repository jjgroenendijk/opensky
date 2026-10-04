---
type: File Format
title: Control map
description: The text file interface\controls\pc\controlmap.txt that lists the game's input
  events and their default keys, and how OpenSky reads it.
tags: [format, input, controls, ui]
---

# Control map

`interface\controls\pc\controlmap.txt` lists every input event the game knows, grouped by
context, with its keyboard, mouse, and gamepad inputs. It sits in `Skyrim - Interface.bsa`.
OpenSky reads it for the default keys and never writes it.

Source: the header comment of the install's own file, and the UESP page
"Skyrim:Controls". Confirmed by parsing the installed file.

## Lines

- The file is plain text. A line starting with `//` is a comment.
- A blank line ends a context. The last comment before the first event names the context,
  such as `Main Gameplay` or `Menu Mode`.
- An event line has tab-separated fields. A run of tabs is one separator.

| Field | Meaning |
| --- | --- |
| 1 | Event name, such as `Forward` or `Quick Map` |
| 2 | Keyboard input |
| 3 | Mouse input |
| 4 | Gamepad input |
| 5 | Keyboard remappable: `0` or `1` |
| 6 | Mouse remappable: `0` or `1` |
| 7 | Gamepad remappable: `0` or `1` |
| 8 | Optional group flags, hexadecimal |

## Inputs

| Form | Meaning |
| --- | --- |
| `0xff` | Unmapped |
| `0x11` | One code. A keyboard code is a DirectInput scan code (`0x11` is W) |
| `0x02,0x4f` | Either code |
| `0x1d+0xb7` | Both codes held together |
| `!0,Activate` | The inputs of `Activate` in context 0 |

`Menu Mode` uses the `!0,...` form, so the menu keys follow the gameplay keys.

## Where OpenSky differs

- macOS sends Control-click as a right click, so Sneak moves from Left Control to C.
- The free-fly camera adds Fly Up (X) and Fly Down (V) in an OpenSky context.
- Return, keypad Enter, the arrow keys, and Tab also steer menus.
- A remap is stored in OpenSky's own settings file by `context|event`. A key taken by
  another event in the same context swaps with it, so no event is left without a key.

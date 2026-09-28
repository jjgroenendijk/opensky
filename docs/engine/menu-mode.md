---
type: Subsystem
title: Menu mode
description: The menu stack, the switch that sends input to a menu instead of the world, the
  per-menu pause rule, and the clock that makes a pause cause no time jump.
tags: [engine, ui, input, menu, simulation]
---

# Menu mode

When a menu opens in Skyrim, input stops moving the camera, the world freezes, and the frozen
frame keeps drawing with the menu on top. This page covers the engine parts that do that. They
know no menu toolkit: the SWF menus and the HUD use the same stack. These are not AppKit menus.

## Menu stack

A menu name is an opaque string, as in Scaleform: for example `"InventoryMenu"`, `"Console"`, or
`"Dialogue Menu"`. The engine only compares names. It has no list of menus.

The stack has no duplicates. The top menu gets input first. An empty stack is gameplay. A stack
with anything in it is menu mode.

- Closing on an empty stack does nothing, so a stray close in gameplay is harmless.
- Opening a menu that is already open is refused, and the caller is told. Scaleform opens one
  menu per name.
- A menu can be closed by name from any position, because Scaleform closes by name. Closing all
  returns to gameplay.

## Controller

`MenuModeController` owns the stack and runs on the main thread, like the renderer. It reports two
values: where input goes (world or menu) and whether the world is paused. It calls
`onModeChange` only when one of them changes.

In menu mode, an input event goes to the attached menu consumer. With no consumer attached, the
event is swallowed, but still kept from the world.

Menu events are small and know no toolkit: move in a direction, accept, cancel, and pointer
movement.

## Pause per menu

Most menus pause the world. The [dialogue menu](/engine/dialogue-menu.md) does not: it takes input
while the world keeps running, because the voice, the speaker turning, and lip sync all run on the
world clock. So each menu is opened with a policy: "pauses world" (the default) or "leaves world
running". Only `"Dialogue Menu"` uses the second.

The policy is per menu, because two menus can be open at once. The system menu over a
conversation still pauses. Closing it gives the running world back to the dialogue. A closed
menu's policy goes with it.

Input target and pause no longer always change together. The app releases held world keys when the
input target changes, not when the pause changes. Otherwise a key held into a non-pausing menu
would keep moving a camera nobody is steering.

## Input switch

The game view asks the controller before handling each event. In menu mode it stops feeding the
camera and sends menu events instead:

| Input | Menu event |
| --- | --- |
| WASD, arrow keys | Move |
| Return, keypad Enter, mouse click | Accept |
| Escape | Cancel |
| Mouse movement | Pointer |

Key releases and other keys are swallowed, so no world key sticks. The pointer is left free,
because a menu wants a visible cursor. Entering menu mode also releases all held camera keys.

## World pause

Each timed system (camera, weather, animation) has its own frame clock. Each frame the clock
returns the time since the last frame, clamped to 0.1 seconds. While paused it returns 0, but
still moves its mark to now. So after a pause of any length, the next frame gets one normal step,
never the whole paused time.

The animation step also drives particles and rain. So a zero step freezes game time, camera,
animation, weather, particles, rain and snow, and the [Papyrus world runtime](/engine/papyrus-world.md)
together. The VM shows why the pause is a clock and not a branch: its frame hook still runs, with
a step of 0, so nothing in it needs to know a menu is open. Offscreen renders apply the same rule
to their fixed 1/30 second step.

Drawing is not paused. A paused frame still encodes, presents, and draws the
[screen-space UI](/rendering/ui.md). The world just holds still.

## Users of the stack

- The [system menu](/engine/system-menu.md) is a menu consumer. Esc, Return, and the move keys
  drive its choices while the world is paused.
- Developer > UI Lab has a menu mode preview. Push, Pop, and Clear open and close placeholder
  menus named `UILabMenu1`, `UILabMenu2`, and so on, so repeated pushes never hit the duplicate
  rule. It shows menu mode, the top menu, the depth, and the pause state. It attaches no consumer,
  so its events are swallowed.

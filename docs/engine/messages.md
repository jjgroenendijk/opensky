---
type: Subsystem
title: Messages, notifications, and help messages
description: How a MESG record becomes text, and how notifications, help messages, and
  message boxes reach the screen and answer scripts.
tags: [engine, ui, scripting]
---

# Messages, notifications, and help messages

A `MESG` record is either a notification (one line at the top left of the HUD) or a message
box (a modal window with buttons). Scripts show them with `Message.Show`,
`Debug.Notification`, `Debug.MessageBox`, and `Message.ShowAsHelpMessage`. The record layout
is on the [message records](/formats/messages.md) page.

## Building the text

1. The `DESC` text is looked up in the `.dlstrings` table, and the `FULL` title in the
   `.strings` table.
2. `Message.Show` passes up to nine floats. Each `%[flags][width][.precision]f` token takes
   the next one, in order. A missing argument is 0, as the defaults of `Show` are. `%%` is a
   percent sign. A `%` that starts no token stays as it is.
3. A message whose `QNAM` names a quest gets its alias tags filled, such as
   `<Alias=Target>`, with the same rules as [journal](/engine/journal.md) text.
4. A message box keeps only the buttons whose conditions pass, each with its `MESG` button
   index. A box with no visible button gets one OK button at index 0.
5. Text is cut at 1,023 characters, the Creation Kit limit for a message box.

Source: the Creation Kit wiki pages "Message" and "Show - Message", read through the
Wayback Machine (see [environment](/tools/environment.md)). The wiki gives the token format
and the limit. The nine-argument limit is the Papyrus signature of `Show`.

## Notifications

A notification shows for its `TNAM` seconds, or 3 seconds when the record has none. At most 3
show at once. Later ones wait in order and show as earlier ones leave. The same line posted
twice in one frame shows once, because two scripts that react to one event often post the
same text. The timing and the limit of 3 are OpenSky's choice; no source gives the game's.

OpenSky draws a notification by calling `ShowMessage` on the HUD movie, and a help message by
calling `ShowTutorialHintText`. The argument shapes come from the movie's own function
parameters, which the HUD real-data test records.

Notifications and help messages use real time. They keep counting while a menu pauses the
world.

## Help messages

`Message.ShowAsHelpMessage(event, duration, interval, maxTimes)` shows a message until the
player does the input event, such as `Jump`. Per the Creation Kit wiki, the event "both
identifies and ends the help message". Rules:

- One help message shows at a time. A new one replaces the old one.
- It shows for `duration` seconds, waits `interval` seconds, and shows again. A duration of 0
  or less keeps it on screen until the event.
- `maxTimes` caps how often it shows. 0 or less means no limit.
- Once the player does the event, the event is done. No help message for it shows again until
  `Message.ResetHelpMessage(event)`.
- Event names match without case.

The count of times shown and the done flag per event are saved in the
[`HELP` save chunk](/formats/opensky-save-world-chunks.md), so a done tutorial stays done after
a load. OpenSky reports the `Jump`, `Sneak`, and `Activate` events from their keys, and the
`Look` event when the pointer turns the view. The opening cart ride shows "Use [Look] to look
around." with the `Look` event (`QF_MQ101_0003372B` calls `ShowAsHelpMessage` with it), so it
stays until the player looks around.

## Message boxes

A box pauses the world and takes the keyboard, like the other menus. One box shows at a time.
Later ones wait in order.

- Up and down move the highlight, and the list wraps around. Enter picks the highlighted
  button. A click on a row picks it.
- Escape closes a box that has one button, as if OK was picked. A box with several buttons is
  a question, so Escape does nothing.
- `Message.Show` on a box suspends the calling script. When the box closes, the call returns
  the `MESG` index of the picked button. A hidden button keeps its index, so a script sees the
  same number as in the game.
- `Debug.MessageBox` gets one OK button and returns at once; no script waits.

The world resumes when the last waiting box closes.

`Interface\messagebox.swf` draws the box. The movie registers four callbacks, and OpenSky
calls them in this order: `setMessageText(text, false)`, `setIsVertical(more than two
buttons)`, `setIsCancellable(one button, 0)`, and `setButtons(true, label, ...)`. A click
calls `buttonPress(index)`, where `index` counts the buttons that were sent. The keys stay
with OpenSky, which moves the movie's focus to the highlighted button so the movie draws
the highlight.

## Help topics

The help menu (`Interface\tutorialmenu.swf`) shows one long help text. The topics are the
`MESG` records whose editor ID starts with `Help` and ends with `Long`, such as
`HelpAlchemyLong` (Creation Kit wiki "Message", <https://ck.uesp.net/wiki/Message>). The
title is the record's `FULL` name and the text its `DESC`.

The engine calls `InitExtensions` and `SetPlatform`, sets `/Menu_mc/TitleText`, assigns the
text to the `text` property of `/Menu_mc/HelpText`, and calls `ApplyButtonArt`. That
function replaces each `[Event]` tag, such as `[Activate]`, with the key: it asks the
engine `GetButtonFromUserEvent(event)`, and OpenSky answers with the key bound to that
control. The exit button calls `CloseMenu`.

The game opens a topic from the Help page of the journal.

## Differences from the game

- `LocalizedStrings` reads the string tables of `Skyrim.esm` only. A message from a DLC
  plugin may show the wrong text or none.
- Without the `MessageBox` movie, for example with menu movies off, the box is drawn as
  OpenSky overlay text.

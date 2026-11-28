---
type: Subsystem
title: Gameplay HUD
description: How the vanilla hudmenu.swf becomes the gameplay HUD - the observed engine-to-movie
  functions and argument shapes, compass heading mapping, authored placeholder clips, and the HUD's
  own SWF layer under the menus.
tags: [rendering, ui, swf, hud]
---

# Gameplay HUD

The gameplay HUD is the vanilla `Interface\hudmenu.swf`, loaded through the
[virtual file system](../formats/vfs.md) and run by the [AS2 runtime](../engine/as2-runtime.md) on the
[SWF layer](swf-layer.md). Before it publishes any state, the engine checks that the
functions it needs exist on `/HUDMovieBaseInstance`. Missing game data, a missing function, or a
renderer failure leaves the HUD off and logs the reason. It never stops the 3D world from starting.

## The movie's functions

The public SWF format does not describe this GFx contract. The names and argument shapes below were
observed by probing the installed movie. It starts with 203 display nodes and no faults.

| Function | What the engine sends |
| --- | --- |
| `SetCrosshairEnabled` | Keeps the vanilla crosshair visible |
| `SetHealthMeterPercent`, `SetMagickaMeterPercent`, `SetStaminaMeterPercent` | A percent, 0 to 100. The engine clamps the fraction to 0 to 1 and multiplies it by 100, so 0.75 reaches the movie as 75 |
| `SetCrosshairTarget` | The interaction prompt, such as `Open <door name>`, or an empty hidden target |
| `CompassTargetDataA` | Four numbers per marker: heading, Flash `_alpha`, the movie's own marker type value, and Flash scale |
| `SetCompassMarkers` | Applies that array |
| `SetCompassAngle` | The camera heading. Also keeps the compass visible |

The marker field order comes from the movie's own reader of `CompassTargetDataA`. Alpha and scale
use Flash's 0 to 100 property units. The meters are fed from the
[actor value store](../engine/actor-value-store.md#hud-bars), and the prompt and marker from
[interaction](../engine/interaction.md).

Heading zero is north (world +Y), and east (+X) is 90. OpenSky keeps headings in 0 up to 360. The
player and compass angles get the same camera yaw. A local visual check confirmed that heading zero
centers the movie's north marker, and that publishing a prompt does not move the compass.

## Crosshair item stat

`SetCrosshairTarget` takes ten arguments: `abActivate, aName, abShowButton, abTextOnly,
abFavorMode, abShowCrosshair, aWeight, aCost, aFieldValue, aFieldText`. The movie adds a field
line only when `aFieldValue` is not `undefined`, and formats it as the rounded number and the
label. As observed in the game, the crosshair on a loose weapon sends its damage and
`sHUDDamage` ("DAMAGE"), and on loose armour its rating and `sHUDArmorRating`
("ARMOR RATING"). Every other target leaves the field `undefined`.

OpenSky sends the numbers the inventory item card shows. The game sends the damage and rating
the player would get with their skill and perks, and a damage for ammunition; OpenSky does not
yet.

## Authored placeholder clips

The installed movie starts with authoring samples visible under
`/HUDMovieBaseInstance/RolloverInfoInstance` and `/HUDMovieBaseInstance/SubtitleTextHolder`. Start-up
hides both, so raw font markup and `Dialogue Line 1Dialogue Line 2` do not show in play.

`/HUDMovieBaseInstance/GrayBarInstance` is the thin line between an item's name and its weight
and value, just below the crosshair. It is visible from the first frame too, so start-up hides it
with the item info until OpenSky publishes item info.

The subtitle holder is also used for real. Writing a line sets
`/HUDMovieBaseInstance/SubtitleTextHolder/textField` and shows the holder. Clearing the line hides the
holder, so no empty box is left ([dialogue menu](../engine/dialogue-menu.md)).

The meters are the clips `/HUDMovieBaseInstance/Health`, `Magica`, and `Stamina`, as spelled in the
movie. Hiding a meter hides its clip. Crosshair and compass visibility use the movie's own setters.

## HUD modes

The movie hides and shows its parts by HUD mode. `/HUDMovieBaseInstance.HudElements` lists the
elements, and each element has a `true` field for every mode it shows in, such as `All`,
`StealthMode`, or `CartMode`. `ShowElements(mode, show)` on `/HUDMovieBaseInstance` puts a mode on
the movie's mode stack when `show` is true, and takes it off when `show` is false. An element
shows only when the top mode is one of its modes. After `StealthMode` and then `CartMode` are put
on, taking off `StealthMode` leaves `CartMode` on top. These facts were observed by probing the
installed movie with `openskycli swf movie-probe`.

The movie names 14 modes. OpenSky drives the six that follow the player and the scripts, bottom
first:

| Mode | When OpenSky puts it on | What it hides of the base mode |
| --- | --- | --- |
| `HorseMode` | The player rides a horse | Stamina meter, crosshair, item info, arrow info, stealth meter |
| `WarHorseMode` | The player rides a horse with a weapon drawn | Item info, stealth meter |
| `Swimming` | The player swims | Stealth meter |
| `StealthMode` | The player sneaks | Crosshair |
| `CartMode` | `Game.SetHudCartMode` | All but messages, subtitles, and tutorial hints |
| `MovementDisabled` | `DisablePlayerControls` turned movement off | As `CartMode`, but quest updates stay |

"Item info" is the activate button, the item name and info, and the gray bar between them. Only
one of the first four is on at a time, in the order of the table. `MovementDisabled` sits above
`CartMode`: the Creation Kit wiki notes that disabling movement during cart mode loses cart mode
until movement comes back ([SetHudCartMode](https://ck.uesp.net/wiki/SetHudCartMode_-_Game)).
`WarHorseMode` follows the game's rule in [HUD under menus](#hud-under-menus).

OpenSky takes every shown mode off and puts the new stack on whenever the stack changes, so the
movie's stack always matches. The movie's own setters, such as `SetCompassAngle` and
`SetCrosshairTarget`, do not show a part that a mode hides. OpenSky's own switches write
`_visible` on the meters, the enemy health bar, the item info, and the subtitle holder, the same
property the modes write. So after each mode change OpenSky applies them again, and it never shows
one of them while the top mode hides it. A HUD movie that starts again, such as after a menu, gets
the modes again.

`openskycli game debug cartmode on|off` sets cart mode. `state menu` shows `hud.cartMode` and the
stack as `hud.modes`.

## HUD under menus

The main menu is the exception to what the HUD shows, not to whether it is open. When the game
closes all menus, for example on a quit to the main menu, it keeps the HUD open, and the main menu
does not hide the menus below it. Even so, the title screen shows no compass, crosshair, or meters.
What hides them there, and what shows them again when a game starts or loads, is not known yet.
OpenSky hides the HUD layer while the title menu or the title sequence is shown, and shows it
again when they close; `state menu` shows this as `hud.underTitle`.

The game keeps drawing the HUD under every menu. No menu closes it. A menu changes only the HUD
mode: when it opens it puts its mode on the movie's stack through `ShowElements(mode, true)`, and
when it closes it takes the mode off. The movie decides which parts each mode shows. Mode changes
are queued and applied in order on the HUD's next update.

| Menu | Mode |
| --- | --- |
| Dialogue | `DialogueMode`; see below |
| Barter, container, gift, inventory, magic, crafting stations | `InventoryMode` |
| Lockpicking | `InventoryMode`, once its movie has loaded |
| Training | `BarterMode`; no other menu uses it |
| Tween menu | `TweenMode`, put on when the menu shows |
| Journal and system menu (`Quest_Journal`) | `JournalMode` |
| Map | `WorldMapMode` |
| Book and note | `BookMode` |
| Sleep and wait | `SleepWaitMode` |
| Favourites, level-up, skills, console, message box, loading screen | No mode |

Dialogue hides itself under a menu that pauses the game, such as barter, gift, or a container
opened from a conversation. Its movie turns invisible, `DialogueMode` comes off, and dialogue
ignores input. When no pausing menu is left open, the movie shows again and `DialogueMode` goes
back on. A hide message with the fade flag first calls the movie's `StartHideMenu` and waits for
its `FadeDone` call.

Modes stack. With the Tween menu open, opening the inventory puts `InventoryMode` above
`TweenMode`, and closing the inventory leaves `TweenMode` on top. While the loading screen is
open, the HUD ignores its data updates but still applies mode changes.

The map fades the screen as it opens and closes. The map transition time is 0.75 s by default.
The fade on opening lasts 0.7 times that, 0.525 s; the fade on closing 0.75 times, 0.5625 s. Both
are skipped while every menu is being closed at once, such as when a loading screen starts.

Some modes follow the player, not a menu:

| Mode | On while |
| --- | --- |
| `StealthMode` | The player sneaks; the stealth meter also gets `FadeIn` or `FadeOut` |
| `Swimming` | The player swims; checked on every HUD update |
| `MovementDisabled` | Player movement is disabled; not changed while dialogue is open |
| `HorseMode` | The player rides |
| `WarHorseMode` | The player rides and draws a weapon; off when the weapon is sheathed or the player dismounts |
| `VATSPlayback` | A kill camera plays |
| `CartMode` | A script turns it on |
| `Favor` | Follower command mode, below |

`Favor` follows an actor's doing-favour state, which `Actor.SetDoingFavor` also sets. When the state
turns on, any other commanded actor is released, this actor becomes the commanded one, a 40 s wait
timer starts, and the HUD adds the favour input context. When it turns off, the commanded actor is
cleared and the context goes. The HUD itself ends favour mode on `Cancel` or when it is hidden.

The HUD resets when a loading screen ends while the HUD is open: after a new game, a load, a door,
or fast travel. A cell change without a loading screen does not reset it. The reset:

1. empties `MessagesInstance.MessageArray` and `ShownMessageArray`;
2. clears the tutorial hint to empty text and the subtitle to one space;
3. empties `HUDModes` and puts `All` on;
4. puts `Favor` on when the player still commands an actor, `HorseMode` when the player rides,
   `WarHorseMode` when the player rides with a weapon out, and `MovementDisabled` when movement is
   disabled.

The HUD root's alpha is the HUD opacity setting times 100. The crosshair state is set to `Alert`
or `Normal`, then the movie's `ValidateCrosshair` runs. `SetCrosshairEnabled` passes the
crosshair setting.

## Timing

HUD changes are collected and applied once between frames. A target change only marks the prompt
and marker dirty, and the frame hook changes the renderer.

The HUD movie's timeline runs by real time, also while a menu pauses the game. OpenSky steps it
in whole movie frames at the movie's own frame rate, and moves it by at most 1/24 s of time in one
display frame, so a stall does not play seconds of animation at once. The timeline matters
because the movie animates its own changes. A tutorial
hint hidden with `ShowTutorialHintText("", false)` does not vanish at once: it starts a fade-out
that takes movie frames. Probed offscreen with the installed movie, the hint is still fully drawn
after 0 and 1 movie frames and gone after 40. Notification lines from `ShowMessage` fade out the
same way.

The HUD movie asks the engine for key art with `GetButtonFromUserEvent`, as the help menu does. A
hint such as `Use [Look] to look around.` shows the key bound to `Look` in place of the tag.

## The HUD layer

The HUD draws on its own SWF layer, under the menu layer
([SWF layer](swf-layer.md#layers)). A menu movie takes the menu layer and leaves the HUD
running under it. The HUD Opacity setting and a loading screen's cover reach only the HUD layer.

OpenSky puts the menu modes on in the order the menus opened, above the modes that follow the
player. `Favor` is on while the player chooses a target in
[follower command mode](../engine/follower-commands.md), and goes below the other player modes, in
the order of the reset above. `Favor` hides the three meters. The menu modes hide every part
OpenSky also switches: the meters, the enemy health bar, and the item info. Which parts each menu
mode shows comes from the movie's element list:

| Mode | Shows |
| --- | --- |
| `InventoryMode`, `TweenMode`, `BookMode` | Messages, quest updates |
| `DialogueMode` | Messages, quest updates, compass |
| `BarterMode` | Messages, quest updates |
| `WorldMapMode` | Messages |
| `JournalMode`, `SleepWaitMode` | Nothing: no element names them |
| `Favor` | All but the three meters |

## Where OpenSky differs

- Lockpicking puts `InventoryMode` on as soon as the menu opens, not once its movie has loaded.
- OpenSky builds the stack in a fixed order: the player modes, then the menu modes. The game
  stacks each mode in the order its event happened, so sneaking with a menu open puts
  `StealthMode` above the menu's mode there.

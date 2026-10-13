---
type: Subsystem
title: Skills menu
description: The level-up pick, the skill ring, the perk trees, and legendary skills, shown
  through the game's own levelupmenu.swf and statsmenu.swf movies.
tags: [engine, menus, progression, perks, swf]
---

# Skills menu

The skills menu is where the player spends what [character leveling](/engine/character-leveling.md)
earns: an attribute pick, perk points, and legendary skills. The Quick Stats key opens it
(`/`, controlmap event `Quick Stats`, scan code 0x35).

The menu has three parts:

- A pure model holds the page and the selection.
- A coordinator on the menu stack carries out the spends through the progression module.
- Two movie bridges send the model to the game's movies.

## Pages

| Page | Shown when | Keys |
| --- | --- | --- |
| Level up | An attribute pick is owed | Left and right pick Magicka, Health, or Stamina; accept spends the pick |
| Skills | No pick is owed | Left and right turn the ring; up or accept opens the tree |
| Perks | A tree is open | Arrows move between boxes on the grid; accept buys the next rank; down from the lowest box or cancel goes back |
| Legendary | Jump was pressed on a skill at 100 | A yes or no question; yes makes the skill legendary |

The ring follows the order of the Dragonborn altar's skill list in `DLC2MiraakAltarScript`:
the six magic skills, then the six warrior skills, then the six thief skills. Vanilla draws
the constellations in the same order.

In the tree, "up" picks the nearest box above. Sideways distance counts twice, so up follows a
branch before it jumps to a neighbour.

## Legendary key

Making a skill legendary uses the Jump key on a keyboard (Space) and the Y button on a gamepad.
`controlmap.txt` has no menu event for it. The gamepad Y button is Jump's own button
(`0x8000`), so OpenSky sends a `yButton` menu event when Jump is pressed in a menu.

## The two movies

The level-up pick and the skill ring are two movies on one SWF layer. The coordinator loads
`levelupmenu.swf` while a pick is owed, and `statsmenu.swf` after the last pick.

### levelupmenu.swf

Observed in the install's movie:

- `InitExtensions` adds the press listeners of `HealthButton`, `MagickaButton`, and
  `StaminaButton` under `/LevelUpMenu_mc`.
- A pressed button calls `GameDelegate.call("addHealth")`, `addMagicka`, or `addStamina`
  with no arguments, then `PlaySound("UIMenuOK")`.

The engine model owns the keyboard selection. It moves the movie's focus to the matching
button, and a click on a button makes the same pick as the accept key.

### statsmenu.swf

The `StatsMenu` class registers these `GameDelegate` callbacks in `InitExtensions`:
`SetDescriptionCard`, `SetPlayerInfo`, `UpdateSkillList`, `SetDirection`, `HideRing`,
`SetStatsMode`, `SetPerkCount`, and `ShowLegendaryButtonHint`.

| Call | Arguments |
| --- | --- |
| `SetPlayerInfo` | name, level, level meter (0 to 100), race, then current, maximum, and colour for magicka, health, and stamina |
| `SetDescriptionCard` | perk mode, name, meter, description, requirement, skill level, skill name, legendary count |
| `SetStatsMode` | `true` for the stats page, `false` for the level-up state; perk points |
| `SetDirection` | ring angle: position times `SKILL_ANGLE` (20) |
| `UpdateSkillList` | whether to capitalise names; reads `StatsMenu.SkillStatsA` |

The engine fills two arrays on the class before it calls the movie:

- `SkillStatsA`: five values per skill: level, name, meter (0 to 100), colour, legendary
  count.
- `PerkNamesA`: three values per perk: HTML name, x, and y, each 0 to 1 of the stage.

`SetStatsMode` was read from the disassembly: `abStats` true selects `STATS`, false
selects `LEVEL_UP`. A colour argument is an HTML colour string; `undefined` leaves the
text white.

### The perk sky

Vanilla draws the perk stars, their lines, and the sky behind the ring in 3D, outside the
movie. OpenSky draws them too: the [perk sky](/engine/perk-sky.md) page has the meshes, the
layout, and the camera. The movie places each perk name where its star lands on screen, and
its `MoveCamera` calls drive the opening camera move.

## Legendary skills and the Dragonborn altar

Both clear one skill's tree and refund one perk point per owned rank:

| | Legendary skill | Dragonborn altar |
| --- | --- | --- |
| Needs | the skill's base at 100 | one dragon soul and at least one perk in the tree |
| Skill afterwards | `fLegendarySkillResetValue`, else 15; its progress is cleared | unchanged |
| Counted | the skill's legendary count goes up by one | nothing |

Sources: UESP "Skyrim:Skills" for legendary skills. `DLC2MiraakAltarScript` in the install
for the altar: it reads `DragonSouls`, refuses a tree with no perks, removes each perk of the
`DLC2Perks<Skill>` list, and refunds with `Game.AddPerkPoints`. Skyrim.esm has no
`fLegendarySkillResetValue` record, so the fallback of 15 applies to a vanilla install.

The legendary counts are saved in their own `PLGD` chunk beside `PLVL`
([save chunks](/formats/opensky-save.md#chunks)). `PLVL` entries carry no length, so a new
field there would break older readers.

## Controls

World > Character > Skills Menu opens the menu and sends each key. It also switches between
the movies and OpenSky's rows; the readout shows the rows in either case. Sky shows or hides
the perk sky, and the readout's sky line gives its draw count, its turn, and whether the
ring or a tree is in view.

World > Progression > Skills has Make legendary and Reset tree for the chosen skill, and
shows each skill's legendary count and the current experience rate.

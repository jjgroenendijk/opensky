---
type: File Format
title: Game settings (GMST)
description: Typed GMST DATA, the movement settings, and which plugin wins.
tags: [format, plugin, esm, gmst, movement, load-order]
---

# Game settings (GMST)

A `GMST` record is one game setting. Its identity is its `EDID` (editor ID), not its
FormID. When two plugins have a GMST with the same `EDID`, the later plugin in load order
wins, even when the FormIDs differ. `EDID` matching ignores case.

Sources: xEdit
[`wbGMSTUnionDecider`](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsCommon.pas)
and the
[`GMST` record definition](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsTES5.pas).

## Typed DATA

The first letter of the `EDID` sets the type of `DATA`:

| Prefix | Type | `DATA` |
| --- | --- | --- |
| `s` | string | uint32 string-table ID if the plugin is localized, else a zstring |
| `i` | integer | int32 |
| `f` | float | float32 |
| `b` | Boolean | uint32, only `0` or `1` |

`EDID` and `DATA` must each appear once. Numbers must be exactly 4 bytes. OpenSky skips a
bad record. A bad record never removes a good value from an earlier plugin.

## Movement settings

The Creation Kit [settings list](https://ck.uesp.net/wiki/Category:Settings) names these
settings:

| Value | Editor ID | Units | Fallback |
| --- | --- | --- | --- |
| Walk speed | `fMoveCharWalkBase` | world units per second | 100 |
| Run speed | `fMoveCharRunBase` | world units per second | 370 |
| Step height | none found | world units | 32 |

`Skyrim.esm` has `fMoveCharWalkBase = 100`. It has no `fMoveCharRunBase`, so OpenSky uses
the documented default. No source and no official plugin gives a GMST for step height. So
OpenSky uses 32 and labels it as its own fallback. It does not guess a name.

In one physics step, the player moves `(running ? runSpeed : walkSpeed) * fixedTimeStep`.

`openskycli gmst movement` prints each value, its units, and which plugin set it.

## Reading a setting

A settings struct holds the vanilla values and lays each setting the load order defines over
one field. A missing setting, a wrongly typed one, or a float that is not finite keeps the
vanilla value. An integer setting may fill a float field. A float with no fraction may fill an
integer field.

A string setting holds a string-table ID in a localized plugin. It resolves through the string
table of the plugin that set it ([string tables](/formats/strings.md)).

A feature that shows several string settings lists them as one enum, whose raw values are the
editor IDs, and reads them through `GameSettingTexts`. Each case carries OpenSky's own words
as a fallback, for a load order without the setting. Examples: `RestText` (`sNoSleep...`),
`ActivationText` (`sTake`, `sSteal`), `SaveNoticeText` (`sAutoSaving`), and `CastNoticeText`
(`sMagicCastInsufficientMagicka`).

## Settings the game never uses

`Skyrim.esm` keeps settings of older games, and texts of consoles and online services. The
Creation Kit [settings list](https://ck.uesp.net/wiki/Category:Settings) says: "Note that while
all game settings are loaded, not all of them are used. It seems that Bethesda doesn't remove
game settings from older games". Its "Featured Games" column and its descriptions mark most of
them, for example `sVDSGManual`: "Unused UI string from Fallout 3's loading screens".

`GameSettingsUnused` lists these settings with one reason each:

| Reason | Examples | Why OpenSky does not read them |
| --- | --- | --- |
| V.A.T.S. | `fVATSPlaybackDelay` | Fallout targeting. Skyrim has none |
| Action points | `fActionPointsReload` | Only V.A.T.S. spends them |
| Firearms | `fGunSpreadArmBase`, `fWeaponConditionJam1` | Guns, grenades, and item condition are Fallout systems |
| Fallout systems | `fKarmaModStealing`, `sRepairCost`, `sFullHealth` | Karma, chems, repair, the Pip-Boy and its notes, radio, hacking, traits |
| Oblivion | `fMoveEncumEffect`, `sHolidayNewLifeFestival` | The wiki marks them "Unused". UESP "Skyrim:Calendar": "no holidays were specifically given" |
| Marked unused | `sHeavyArmorSink` | The wiki says "Unused"; `sHairColor0` to `15` hold their own names |
| Creations | `sReportModConfirm` | The Bethesda.net Creations manager. OpenSky does not connect to it |
| Consoles | `sKinectCantInit`, `sNoDeviceSelected` | Xbox, Kinect, and console storage texts |
| Movie labels | `sActorFade`, `sConfirmSave` | `interface\quest_journal.swf` builds the settings and save pages from its own `$` keys, such as `$Actor Fade`, in `interface\translate_english.txt` |
| Reward XP | `iXPRewardPickLock`, `sRewardXP` | UESP [Skyrim:Leveling](https://en.uesp.net/wiki/Skyrim:Leveling) gives level experience only for skill increases. A picked lock trains Lockpicking through `fSkillUsageLockPick` |
| Speech globals | `iSpeechChallengeDifficultyEasy` | UESP [Skyrim:Speech](https://en.uesp.net/wiki/Skyrim:Speech) gives the persuasion thresholds 10, 25, 50, 75, 100. A line tests the globals `SpeechVeryEasy` and so on ([CK tutorial](https://ck.uesp.net/wiki/Tutorial:_Dialogue_Speech_Checks)) |
| Replaced notices | `sQuestAddedText`, `sDungeonCleared`, `sSneakAttack` | The HUD shows these notices with `sHUDStarted`, `sHUDCompleted`, `sCleared`, and `sSuccessfulSneakAttackMain`. See [journal](/engine/journal.md) and [melee damage](/engine/melee-damage.md) |
| Debug dialog | `sContinueText`, `sAbortText` | The developer assert box ("Continue Running Executable?", Abort, Retry, Ignore). A release build never opens it |

A setting on this list counts as done in the [gap report](/tools/gaps.md). A setting the wiki
does not mark, and whose system Skyrim has, stays off the list even if OpenSky lacks the system.

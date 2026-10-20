---
type: Subsystem
title: Training
description: How a trainer raises a skill for gold, what it costs, and when it refuses.
tags: [engine, progression]
---

# Training

A trainer sells skill points for gold. The trainer's class says which skill and up to which
level. Source: UESP "Skyrim:Trainers" (<https://en.uesp.net/wiki/Skyrim:Trainers>).

## Who trains what

`CLAS` `DATA` byte `0x04` is the skill, as the actor value index minus 6. Byte `0x05` is the
level the trainer teaches up to. A level of 0 means the class trains nothing
([actor records](/formats/actors.md)). UESP lists three trainer levels: up to 50, 75, and 90.

The game opens training from the trainer's dialogue: the topic's script fragment calls
`Game.ShowTrainingMenu` (see [training menu](#training-menu)). The panel's Train control in
World > Progression > Skills trains with the nearest actor, without the dialogue.

## Cost

UESP gives the cost of `n` sessions from skill level `b`:

| Skill level | Cost of `n` sessions |
| --- | --- |
| up to 50 | `n(10b + 5n + 45)` |
| above 50 | `n(30b + 15n + 35)` |
| above 75 | `n(50b + 25n + 25)` |

One session (`n = 1`) costs `10b + 50`, `30b + 50`, or `50b + 50`. The factors 10, 30, and 50
match `fTrainingMultCost` (10) times a tier of 1, `iTrainingExpertCost` (3), or
`iTrainingMasterCost` (5). So OpenSky computes one session as
`fTrainingMultCost * tier * b + 50`. The 50 is in no setting; it comes from the formulas.

Example: Block at 20 costs `10 * 1 * 20 + 50 = 250` gold, the first term of UESP's example.

The gold goes to the trainer's inventory. Speech and Fortify Barter do not change the price.

## Limits

- Five sessions per character level. A level-up resets the count. No setting holds the 5.
- A trainer refuses at or above its level.

Each refusal shows its notice on the HUD:

| Refusal | Notice setting |
| --- | --- |
| Five sessions used | `sCanNotTrainAnymore` |
| At the trainer's level | `sCanNotTrainHigher` |
| Not enough gold | `sInsufficientGoldToTrain` |

A session gives one level's worth of skill experience and counts the "Training Sessions"
misc stat. UESP: "One session of training gives exactly one whole level's worth of XP", which
"benefits from Sleeping and Standing Stone bonuses" but "will not award a bonus level", and
"overflow XP will be lost". So OpenSky multiplies the cost of the next level by the `Mod Skill
Use` perk entry point, raises the skill one level, and keeps at most just under the next
level's cost as progress. The skill level banks character experience like any other skill
level.

The session count is saved in its own `PTRN` chunk ([save format](/formats/opensky-save.md)).

## Training menu

`Game.ShowTrainingMenu` and the trainer's dialogue open `Interface\trainingmenu.swf`. The
engine calls `InitExtensions(0, false)` and fills `/TrainingMenuObj`:

| Field | Text |
| --- | --- |
| `SkillName` | the skill and its level |
| `TrainerSkill` | the trainer's name and maximum level |
| `TimesTrained` | the sessions done and the sessions per level |
| `TrainCost` | the price |
| `CurrentGold` | the player's gold |

`SkillMeter.SetPercent` shows the progress to the next skill level. The movie's train button
calls `Train`, and its exit button calls `Exit`. A refusal stays on the HUD as in the
table above, and the menu stays open.

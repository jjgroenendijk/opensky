---
type: Subsystem
title: Sound mix
description: How the sound categories set each sound's level - static volumes, the menu fade
  and pause, the dialogue duck, the loading pause, and the under-water mute.
tags: [engine, audio, mix, menus, dialogue]
---

# Sound mix

Every sound descriptor (`SNDR`) names a sound category (`SNCT`). The categories form a tree
under `_AudioCategoryMaster`, like the busses of a mixing desk
([Sound Category](https://ck.uesp.net/wiki/Sound_Category)). A sound's level is the product of
what each category on the way to the root does to it.

## What a category does

- **Static volume.** `VNAM` is a level from 0 to 1. The install uses 1.0, 0.9, and 0.7. For
  example, `AudioCategoryMUS` is 0.7 and `_AudioCategoryMaster` 0.9, so music plays at 0.63
  before the player's sliders.
- **Mute when submerged.** `FNAM` flag 0x01. The category is silent while the camera is under
  water. In the install only `AudioCategoryMuteSubmerged` has it.

The default objects (`DOBJ`) name the categories with a rule. The record is merged per tag over
all plugins, because the Survival Mode plugin replaces `DefaultObjectManager` with only its own
seven entries.

| Tag | Meaning | What OpenSky does while it applies |
| --- | --- | --- |
| `PDMC` | Pause During Menu Category (Fade) | In menu mode, fades to silence over `fMenuModeFadeOutTime`, then pauses. Fades back in over `fMenuModeFadeInTime` |
| `PIMC` | Pause During Menu Category (Immediate) | Pauses at once in menu mode |
| `PDLC` | Pause During Loading Menu | Pauses while a loading screen shows |
| `SFDC` | SFX To Fade In Dialogue Category | Falls to `SoundCategoryMix.dialogueDuckLevel` during a conversation |
| `NDSC` | Non-Dialogue Voice Category | The same as `SFDC`, so other actors' speech is quieter than the speaker's |
| `MDSC` | Music Sound Category | Falls to `SoundCategoryMix.musicDuckLevel` during a conversation, over `fMusicDuckingSeconds`, and comes back over `fMusicUnDuckingSeconds` |
| `SMSC` | Stats Mute Category | Silent while the skills menu is open |
| `DDSC` | Dialogue Voice Category | Nothing: the speaker stays at full level |

The tree places most game sounds under these categories. For example, the voices sit under
`AudioCategoryVOCGeneral`, whose parent is `AudioCategoryPausedDuringMenu`, so speech holds
still in a menu. The interface sounds sit under `AudioCategorySFX` and keep playing.

The four seconds come from `Skyrim_Default.ini` `[Audio]`: `fMusicDuckingSeconds=6.0`,
`fMusicUnDuckingSeconds=8.0`, `fMenuModeFadeOutTime=3.0`, and `fMenuModeFadeInTime=1.0`.
OpenSky reads them through the same INI chain as the LOD settings, so a user's `Skyrim.ini`
wins. The `SFDC` and `NDSC` fades use the music seconds.

[WARNING] How far music and the dialogue sounds duck is not in the data. The two levels are
OpenSky's values, and the fade timing of `SFDC` and `NDSC` is borrowed from the music duck.
Both are in the [unverified values](/engine/unverified-values.md).

## A sound with no descriptor

Music tracks and the dialogue voice files have no `SNDR`. They take the category their kind maps
to: music takes `MDSC`, the conversation's speaker `DDSC`, and any other voice `NDSC`.

## Rumble

A sound shakes the controller when its output model (`SOPM`) sets Allows Rumble and its
descriptor's `LNAM` sends some of its level to the motors ([sound](/formats/sound.md)). The
strength is the send times the level the listener hears when the sound starts. The rumble
lasts as long as the sound file, and at most `SoundRumble.maximumSeconds` (1).

A blow from the player's weapon plays the weapon's Rumble tab: the left motor strength on the
big motor, the right on the small one, for the tab's seconds ([items](/formats/item-records.md)).

Every rumble follows the Gameplay page's Vibration switch, like a shout's
([shouts](/engine/shouts.md#rumble)).

[WARNING] The game follows the sound's level as it plays. OpenSky takes the level once, at the
start. When the weapon rumble plays, on every blow or only on some, is OpenSky's reading. Both
are in the [unverified values](/engine/unverified-values.md).

## Reading it

`state frame` shows `soundMix`: the inputs (`menuMode`, `loading`, `dialogue`, `submerged`,
`statsMenu`), the `menuLevel`, `dialogueLevel`, and `musicLevel`, and the level and pause of
each role's category.

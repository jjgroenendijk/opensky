---
type: Subsystem
title: Creation Club
description: How OpenSky opens the Creation Club store movie offline, through the
  `codeObj` object the movie calls.
tags: [engine, menu]
---

# Creation Club

The Creation Club menu is the game's store for paid add-ons. It needs the Bethesda.net
service. OpenSky does not connect to it, so the menu opens empty and only closes. The
sidebar opens it (HUD & Interaction > Menu screens, "Creation Club").

## The movie

`Interface\creationclubmenu.swf` holds one clip, `/CreationClub_mc`, with the class
`CreationClubMenu`. It does not call the engine through GameDelegate. Its constructor makes
an empty object, `codeObj`, and the engine fills that object with functions. Measured on
the install, the movie calls these:

| Group | Calls | What OpenSky does |
| --- | --- | --- |
| Store and login | `InitCreationClubMenu`, `PurchaseMod`, `DownloadCreation`, `DownloadAll`, `LoadThumbnail`, `PopulateEULA`, `AcceptLegalDoc`, `attemptLogin`, `createQuickAccount`, `EnterCreditsScreen`, `EnterDetailsScreen`, `onLoginScreenOpen`, `onLoginScreenClose`, `onDisplayImage`, `UnregisterImage` | Nothing |
| Text fields | `startEditText`, `endEditText` | Nothing |
| Sound | `PlaySound`, `PlayOKSound` | Nothing |
| Closing | `confirmCloseManager`, `attemptCloseManager` | Closes the menu |

After it fills `codeObj`, the engine calls `onCodeObjectInit(language)` on the clip, with
`"en"`. The movie then runs its `Init` on the next frame. Before the menu goes, the engine
calls `ReleaseCodeObject`.

Escape closes the menu. In the movie, Escape calls `onExit`, which calls
`codeObj.confirmCloseManager`.

## Differences from the game

- The store shows no add-ons, no credits, and no login screen.
- The game opens it from the main menu. OpenSky opens it only from the sidebar.

---
type: Subsystem
title: Speech checks
description: The bribe price and the intimidation check behind GetBribeSuccess and
  GetIntimidateSuccess, their game settings, and which values are OpenSky's own.
tags: [engine, dialogue, conditions, speech]
---

# Speech checks

A dialogue line can offer a bribe or an intimidation. Its conditions `GetBribeSuccess` (654)
and `GetIntimidateSuccess` (655) decide whether the player succeeds. Both formulas come from
UESP "Skyrim:Speech" (<https://en.uesp.net/wiki/Skyrim:Speech>).

## Bribe

```text
morality = Morality * fBribeMoralityMult + 1
base     = NPC level * fBribeNPCLevelMult + player level
           - (player Speech - NPC Speech - 100) * fBribeSpeechcraftMult
bribe    = round(base ^ fBribeCostCurve * fBribeScale * morality)
```

The UESP formula has unbalanced brackets. OpenSky reads it as above. `GetBribeSuccess` is 1
when the player carries at least the bribe times the "Mod Bribe Amount" perk entry point
(46) in gold.

## Intimidation

```text
player scariness = player level * (1 + max(-1, (player Speech - NPC Speech) / 100))
                   ^ fIntimidateSpeechcraftCurve
NPC scariness    = NPC level * fIntimidateConfidenceMult<Confidence>
```

The "Mod Player Intimidation" perk entry point (43) multiplies the player's scariness.
`GetIntimidateSuccess` is 1 when the player is scarier than the NPC. Confidence is the
actor value 1: 0 Cowardly, 1 Cautious, 2 Average, 3 Brave, 4 Foolhardy.

## Game settings

`Skyrim.esm` sets only `fBribeCostCurve` (1.4), `fBribeScale` (0.5), and
`fBribeSpeechcraftMult` (0.1). A setting the load order does not hold falls back to a value
OpenSky chose, because no source gives the game's built-in default:

| Setting | OpenSky value |
| --- | --- |
| `fBribeMoralityMult`, `fBribeNPCLevelMult` | 1 |
| `fIntimidateSpeechcraftCurve` | 1 |
| `fIntimidateConfidenceMultCowardly` | 0.5 |
| `fIntimidateConfidenceMultCautious` | 0.75 |
| `fIntimidateConfidenceMultAverage` | 1 |
| `fIntimidateConfidenceMultBrave` | 1.25 |
| `fIntimidateConfidenceMultFoolhardy` | infinite, so a foolhardy NPC is never intimidated |

With no settings or no gold count, both conditions fail with the speech reason.

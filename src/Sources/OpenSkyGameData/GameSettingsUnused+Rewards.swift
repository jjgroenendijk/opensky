/// Level experience comes only from skill increases, as UESP "Skyrim:Leveling" gives it
/// (https://en.uesp.net/wiki/Skyrim:Leveling). A picked lock trains the skill through
/// `fSkillUsageLockPick`. The `iMess` settings belong to Fallout's Bloody Mess perk.
nonisolated let rewardXPSettings = [
    "iMessCrippledLimbExplodeBonus",
    "iMessIntactLimbExplodeBonus",
    "iMessTargetedLimbExplodeBonus",
    "iMessTorsoExplodeChance",
    "fExplodeLimbRemovalDelay",
    "iXPBumpBase",
    "iXPDeathRewardHealthThreshold",
    "iXPLevelKillCreatureAverage",
    "iXPLevelKillCreatureEasy",
    "iXPLevelKillCreatureHard",
    "iXPLevelKillCreatureVeryEasy",
    "iXPLevelKillCreatureVeryHard",
    "iXPLevelKillNPCAverage",
    "iXPLevelKillNPCEasy",
    "iXPLevelKillNPCHard",
    "iXPLevelKillNPCVeryEasy",
    "iXPLevelKillNPCVeryHard",
    "iXPRewardKillOpponentAverage",
    "iXPRewardKillOpponentEasy",
    "iXPRewardKillOpponentHard",
    "iXPRewardKillOpponentVeryEasy",
    "iXPRewardKillOpponentVeryHard",
    "iXPRewardDiscoverMapMarker",
    "iXPRewardPickLock",
    "iXPRewardPickLockAverage",
    "iXPRewardPickLockEasy",
    "iXPRewardPickLockHard",
    "iXPRewardPickLockVeryEasy",
    "iXPRewardPickLockVeryHard",
    "iXPRewardSpeechChallengeVeryEasy",
    "sRewardXP",
    "sRewardXPIcon"
]

/// UESP "Skyrim:Speech" gives the persuasion thresholds as 10, 25, 50, 75, and 100
/// (https://en.uesp.net/wiki/Skyrim:Speech), not these values. The CK wiki tutorial
/// (https://ck.uesp.net/wiki/Tutorial:_Dialogue_Speech_Checks) sets them through globals.
nonisolated let speechGlobalsSettings = [
    "iSpeechChallengeDifficultyAverage",
    "iSpeechChallengeDifficultyEasy",
    "iSpeechChallengeDifficultyHard",
    "iSpeechChallengeDifficultyVeryEasy",
    "iSpeechChallengeDifficultyVeryHard"
]

// Game settings Skyrim SE defines but never uses: leftovers from Fallout 3 and Oblivion,
// and texts of consoles and Bethesda.net. `openskycli gaps` counts them as done. The
// Creation Kit settings list (https://ck.uesp.net/wiki/Category:Settings) marks most of
// them. See docs/formats/gmst.md.

import Foundation

nonisolated public enum GameSettingUnusedReason: String, CaseIterable, Sendable {
    /// Fallout V.A.T.S. targeting. Skyrim has no V.A.T.S.
    case vats
    /// Fallout action points, which only V.A.T.S. spends.
    case actionPoints
    /// Fallout guns, grenades, iron sights, auto-aim, limb damage, and item condition.
    case firearms
    /// Other Fallout 3 systems: karma, chems, the Pip-Boy, radio, repair, hacking, traits, and its
    /// sneak and lock texts.
    case falloutSystems
    /// Oblivion leftovers: armour encumbrance, wortcraft, its cursor, and its holidays.
    case oblivion
    /// Settings the Creation Kit wiki marks unused, and the `sHairColor` placeholders whose text is
    /// their own name.
    case wikiUnused
    /// The Bethesda.net Creations manager, which OpenSky does not connect to.
    case creations
    /// Xbox, Kinect, and console storage and profile texts.
    case consoles
    /// Labels and prompts of the settings and save pages. The SE journal movie builds
    /// those pages with its own `$` texts and has no row or prompt that uses these.
    case movieLabel
    /// Fallout experience for kills, locks, and speech challenges, and its Bloody Mess
    /// limb bursts. Skyrim gives level experience only for skill increases.
    case rewardXP
    /// Speech challenge difficulties. A Skyrim persuasion line tests Speech against the
    /// globals `SpeechVeryEasy` to `SpeechVeryHard` in its own conditions.
    case speechGlobals
    /// Lower-case sex words. The pronoun tags of the Creation Kit wiki "Text Replacement"
    /// read the `sPronoun` settings, and the race menu reads `sGenderMale` and `sGenderFemale`.
    case sexWords
    /// Older notice texts. The HUD shows these notices through newer settings:
    /// `sHUDStarted`, `sHUDCompleted`, `sCleared`, and `sSuccessfulSneakAttackMain`.
    case replacedNotice
    /// The developer assert box ("Continue Running Executable?"), which a release build never opens.
    case debugDialog
}

nonisolated public enum GameSettingsUnused: Sendable {
    /// Why the game never reads `editorID`, or nil when it does.
    public static func reason(for editorID: String) -> GameSettingUnusedReason? {
        byName[editorID.lowercased()]
    }

    private static let byName: [String: GameSettingUnusedReason] = names.reduce(into: [:]) {
        for name in $1.value {
            $0[name.lowercased()] = $1.key
        }
    }

    static let names: [GameSettingUnusedReason: [String]] = [
        .vats: vatsSettings,
        .actionPoints: actionPointsSettings,
        .firearms: firearmsSettings,
        .falloutSystems: falloutSystemsSettings,
        .oblivion: oblivionSettings,
        .wikiUnused: wikiUnusedSettings,
        .creations: creationsSettings,
        .consoles: consolesSettings,
        .movieLabel: movieLabelSettings,
        .sexWords: [
            "sSexFemale", "sSexFemalePossessive", "sSexFemalePronoun",
            "sSexMale", "sSexMalePossessive", "sSexMalePronoun"
        ],
        .rewardXP: rewardXPSettings,
        .speechGlobals: speechGlobalsSettings,
        .replacedNotice: [
            "sDungeonCleared", "sQuestAddedText", "sQuestCompletedText", "sQuestUpdatedText",
            "sSneakAttack"
        ],
        .debugDialog: ["sAbortText", "sContinueText", "sDefaultMessage", "sIgnoreText", "sRetryText"]
    ]
}

nonisolated private let vatsSettings = [
    "fActionPointsVATSMeleeMult",
    "fExplodeLimbRemovalDelayVATS",
    "fVATSCameraCutAwayDistance",
    "fVATSCameraDollyMin",
    "fVATSCameraDollyTime",
    "fVATSCamTransRBStart",
    "fVATSCamTransRBStrengthCap",
    "fVATSDamageToWeaponMult",
    "fVATSDistanceFactor",
    "fVATSDOFRange",
    "fVATSDOFStrengthCap",
    "fVATSGrenadeTargetArea",
    "fVATSH2HWarpDistanceMult",
    "fVATSMeleeWarpDistanceMult",
    "fVATSMoveCameraLimbMult",
    "fVATSMoveCameraLimbPercent",
    "fVATSMoveCameraXPercent",
    "fVATSParalyzePalmChance",
    "fVATSPlaybackDelay",
    "fVATSPlayerDamageMult",
    "fVATSPlayerMagicTimeSlowdownMult",
    "fVATSPlayerTimeUpdateMult",
    "fVATSRadialRampup",
    "fVATSRadialStart",
    "fVATSRadialStrength",
    "fVATSRangeSpreadMax",
    "fVATSRangeSpreadUncertainty",
    "fVATSScreenPercentFactor",
    "fVATSShotLongBurstTime",
    "fVATSSmartCameraCheckHeight",
    "fVATSSmartCameraCheckStepDistance",
    "fVATSSpreadMult",
    "fVATSStrangerDistance",
    "fVATSStrangerOdds",
    "fVATSTargetActorZMultFar",
    "fVATSTargetActorZMultFarDist",
    "fVATSTargetActorZMultNear",
    "fVATSTargetFOVMultFar",
    "fVATSTargetFOVMultFarDist",
    "fVATSTargetFOVMultNear",
    "fVATSTargetRotateMult",
    "iVATSStrangerMaxHP",
    "sVatsAimed",
    "sVatsAiming",
    "sVatsBodyPart",
    "sVATSMessageLowAP",
    "sVATSMessageNoAmmo",
    "sVATSMessageZeroChance",
    "sVatsSelect",
    "sVatsTarget"
]

nonisolated private let actionPointsSettings = [
    "fActionPointsAimAdjustment",
    "fActionPointsAttackOneHandMelee",
    "fActionPointsAttackTwoHandMelee",
    "fActionPointsAttackUnarmed",
    "fActionPointsCrouch",
    "fActionPointsFOVMult",
    "fActionPointsHeal",
    "fActionPointsPowerAttackMult",
    "fActionPointsReload",
    "fActionPointsRestoreRate",
    "fActionPointsRunAndGunMult",
    "fActionPointsStand",
    "fActionPointsSwitchWeapon",
    "fActionPointsToggleWeaponDrawn",
    "sActionPointsAttack",
    "sActionPointsCrouch",
    "sActionPointsHeal",
    "sActionPointsPunch",
    "sActionPointsReload",
    "sActionPointsStand",
    "sActionPointsSwitchWeapon",
    "sActionPointsToggleWeaponDrawn"
]

nonisolated private let firearmsSettings = [
    "fAutoAimMaxDegrees",
    "fAutoAimMaxDegrees3rdPerson",
    "fAutoAimMaxDistance",
    "fAutoAimScreenPercentage",
    "fCombatPlayerLimbDamageMult",
    "fDamageGunWeapCondBase",
    "fDamageGunWeapCondMult",
    "fDamageMeleeWeapCondBase",
    "fDamageMeleeWeapCondMult",
    "fDamageToArmorPercentage",
    "fDamageToWeaponEnergyMult",
    "fDamageToWeaponGunMult",
    "fDamageToWeaponLauncherMult",
    "fDamageToWeaponMeleeMult",
    "fGrenadeFriction",
    "fGrenadeRestitution",
    "fGunParticleCameraDistance",
    "fGunShellDirectionRandomize",
    "fGunShellEjectSpeed",
    "fGunSpreadArmBase",
    "fGunSpreadArmMult",
    "fGunSpreadCondBase",
    "fGunSpreadCondMult",
    "fGunSpreadCrouchMult",
    "fGunSpreadDriftMult",
    "fGunSpreadRunMult",
    "fGunSpreadSkillBase",
    "fGunSpreadSkillMult",
    "fIronSightsDOFDistance",
    "fIronSightsDOFRange",
    "fIronSightsDOFStrengthCap",
    "fIronSightsGunMotionBlur",
    "fIronSightsMotionBlur",
    "fProjectileInventoryGrenadeFreakoutTime",
    "fProjectileInventoryGrenadeTimer",
    "fWeaponConditionJam1",
    "fWeaponConditionJam2",
    "fWeaponConditionJam3",
    "fWeaponConditionJam4",
    "fWeaponConditionRateOfFire1",
    "fWeaponConditionRateOfFire2",
    "fWeaponConditionRateOfFire3",
    "fWeaponConditionRateOfFire4",
    "fWeaponConditionRateOfFire5",
    "fWeaponConditionRateOfFire6",
    "fWeaponConditionRateOfFire7",
    "fWeaponConditionRateOfFire8",
    "fWeaponConditionRateOfFire9",
    "fWeaponConditionSpread1",
    "fWeaponConditionSpread2",
    "fWeaponConditionSpread3",
    "fWeaponConditionSpread4",
    "fWeaponConditionSpread5",
    "fWeaponConditionSpread6",
    "fWeaponConditionSpread7",
    "fWeaponConditionSpread8",
    "fWeaponConditionSpread9",
    "sDismemberRobotParticleDefault"
]

nonisolated private let falloutSystemsSettings = [
    "sActiveMineDescription",
    "sAlreadyPlacedMine",
    "fAddictionUsageMonitorThreshold",
    "fKarmaModKillingEvilActor",
    "fKarmaModStealing",
    "fRepairSkillMax",
    "iMineDisarmExperience",
    "iXPRewardHackComputer",
    "iXPRewardHackComputerAverage",
    "iXPRewardHackComputerEasy",
    "iXPRewardHackComputerHard",
    "iXPRewardHackComputerVeryEasy",
    "iXPRewardHackComputerVeryHard",
    "sAmber",
    "sAttributesCount",
    "sAttributesTitle",
    "sBroken",
    "sCantEquipBrokenItem",
    "sCantEquipPowerArmor",
    "sCantRepairPastMax",
    "sChemsAddicted",
    "sChemsWithdrawal",
    "sChemsWornOff",
    "sConfirmAttribute",
    "sInaccessible",
    "sLockBroken",
    "sMagicTypeAddiction",
    "sNoItemsToRepair",
    "sNoRepairHostileActorsNear",
    "sNoRepairInCombat",
    "sNoSpareParts",
    "sPipboyColor",
    "sPleaseStandBy",
    "sRadioSignalLost",
    "sRadioStationDiscovered",
    "sRadioVolume",
    "sRepair",
    "sRepairAllItems",
    "sRepairCost",
    "sAddedNote",
    "sFullHealth",
    "sRepairItem",
    "sRepairServicesTitle",
    "sRepairSkill",
    "sRepairSkillTooLow",
    "sSelectItemToRepair",
    "sSkillsCount",
    "sSkillsTitle",
    "sSneakCaution",
    "sSneakDanger",
    "sSneakDetected",
    "sSneakHidden",
    "sSpeechChallengeFailure",
    "sSpeechChallengeSuccess",
    "sTraitsCount",
    "sTraitsTitle",
    "sVDSGManual",
    "sVDSGPlate",
    "sWeaponBreak",
    "sWhite"
]

nonisolated private let oblivionSettings = [
    "fMoveEncumEffect",
    "fMoveEncumEffectNoWeapon",
    "fWortFailSkillUseMagnitude",
    "iIngredientWortcraftUses",
    "sHolidayEmperorsBirthday",
    "sHolidayFirstPlanting",
    "sHolidayHarvestsEnd",
    "sHolidayJestersDay",
    "sHolidayMerchantsFestival",
    "sHolidayMidYearCelebration",
    "sHolidayNewLifeFestival",
    "sHolidayNorthWindsPrayer",
    "sHolidayOldLifeFestival",
    "sHolidaySecondPlanting",
    "sHolidaySouthWindsPrayer",
    "sHolidaySunsRest",
    "sHolidayTalesAndTallows",
    "sHolidayWarriorsFestival",
    "sHolidayWitchesFestival",
    "sCursorFilename",
    "sMagicTypeWortcraft"
]

nonisolated private let wikiUnusedSettings = [
    "fCombatDamageBonusSneakingMult",
    "sCanNotReadBook",
    "sHairColor0",
    "sHairColor1",
    "sHairColor10",
    "sHairColor11",
    "sHairColor12",
    "sHairColor13",
    "sHairColor14",
    "sHairColor15",
    "sHairColor2",
    "sHairColor3",
    "sHairColor4",
    "sHairColor5",
    "sHairColor6",
    "sHairColor7",
    "sHairColor8",
    "sHairColor9",
    "sHeavyArmorNoJump",
    "sHeavyArmorSink",
    "sQuestFailed"
]

nonisolated private let creationsSettings = [
    "sCantInstallModDependency",
    "sCantInstallModInvalid",
    "sChangedModsResetConfirm",
    "sCloseModManager_Confirm",
    "sConfirmNewMods",
    "sConfirmNewMods_Orbis",
    "sCorruptContentMessage",
    "sDeleteAllModsConfirm",
    "sDeleteLibraryModConfirm",
    "sDeleteModConfirm",
    "sDownloadsAvailable",
    "sDownloadsNotAvail",
    "sFindingContentMessage",
    "sLoadingContentMessage",
    "sLoadVanillaSaveWithMods",
    "sLoadVanillaSaveWithMods_Orbis",
    "sModdedString",
    "sOldDownloadsAvailable",
    "sReportModCat_Explicit",
    "sReportModCat_General",
    "sReportModCat_Harassment",
    "sReportModCat_Impersonation",
    "sReportModCat_PrivateInfo",
    "sReportModCat_Profanity",
    "sReportModCat_Racial",
    "sReportModCat_Religious",
    "sReportModCat_Slander",
    "sReportModCat_Spam",
    "sReportModChooseCategory",
    "sReportModConfirm",
    "sRestartBecauseContentRemoved",
    "sRestartToUseNewContent",
    "sRestartToUseProfileContent"
]

nonisolated private let consolesSettings = [
    "sControllerOption",
    "sLostController",
    "sDevice",
    "sDeviceRemoved",
    "sDisableXBoxController",
    "sGFWLive",
    "sKinectAllyTooFarToTrade",
    "sKinectCantInit",
    "sKinectNotCalibrated",
    "sMenuDisplayShortXBoxSaveMessage",
    "sMenuDisplayXBoxSaveMessage",
    "sNoDeviceSelected",
    "sNoProfileSelected",
    "sRestartSignedOut"
]

// Which graph variables the engine must drive or read, and which members a node
// writes back. `openskycli gaps` counts a variable as left only when it faces the
// engine and no engine code handles it (docs/tools/gaps.md).

import Foundation
import OpenSkyFormatsAnimation

nonisolated public enum BehaviorVariableRoles: Sendable {
    /// The variables the game exposes to Papyrus through `GetAnimationVariable*`,
    /// from https://ck.uesp.net/wiki/List_of_Animation_Variables.
    public static let engineVariables: Set = [
        "bMotionDriven", "IsBeastRace", "IsSneaking", "IsBleedingOut", "IsCastingDual",
        "Is1HM", "IsCastingRight", "IsCastingLeft", "IsBlockHit", "IsPlayer", "IsNPC",
        "bIsSynced", "bVoiceReady", "IsShouting", "bWantCastLeft", "bWantCastRight",
        "bWantCastVoice", "b1HM_MLh_attack", "b1HMCombat", "bAnimationDriven", "bCastReady",
        "bAllowRotation", "bMagicDraw", "bMLh_Ready", "bMRh_Ready", "bInMoveState",
        "bSprintOK", "bIdlePlaying", "bIsDialogueExpressive", "bAnimObjectLoaded",
        "bEquipUnequip", "bAttached", "bEquipOK", "bIsH2HSolo", "bHeadTracking", "bIsRiding",
        "bTalkable", "bRitualSpellActive", "bInJumpState", "bHeadTrackSpine",
        "bLeftHandAttack", "bIsInMT", "bHumanoidFootIKEnable", "bHumanoidFootIKDisable",
        "bStaggerPlayerOverride", "bNoStagger", "bIsStaffLeftCasting", "bPerkShieldCharge",
        "bPerkQuickShot", "IsAttacking", "Isblocking", "IsBashing", "IsStaggering",
        "IsRecoiling", "IsEquipping", "IsUnequipping", "iSyncIdleLocomotion",
        "IsAttackReady_32", "iRightHandType", "iWantBlock", "iAnnotation", "iSyncTurnState",
        "i1stPerson", "iLeftHandType", "iState", "iState_NPCSprinting", "iState_NPCDefault",
        "iState_NPCSneaking", "iState_NPCBowDrawn", "iDualMagicState", "iState_NPCBlocking",
        "iState_NPCBleedout", "iBlockState", "iSyncSprintState", "iIsInSneak",
        "iMagicEquipped", "iEquippedItemState", "iMagicState", "iIsDialogueExpressive",
        "iSyncIdleState", "iState_NPC1HM", "iState_NPC2HM", "iState_NPCBow", "iState_NPCMagic",
        "iState_NPCMagicCasting", "iState_NPCHorse", "iState_HorseSprint",
        "iCharacterSelector", "iCombatStance", "iSyncTurnDirection", "iRegularAttack",
        "iRightHandEquipped", "iLeftHandEquipped", "iIsPlayer", "iGetUpType",
        "iState_NPCAttacking", "iState_NPCPowerAttacking", "iState_NPCAttacking2H",
        "iDrunkVariable", "iState_NPCDrunk", "iTempSwitch", "iState_NPCBowDrawnQuickShot",
        "iState_NPCBlockingShieldCharge", "Speed", "VelocityZ", "camerafromx", "camerafromy",
        "camerafromz", "FemaleOffset", "bodyMorphWeight", "IsInCastState",
        "IsInCastStateDamped", "blockDown", "blockLeft", "blockRight", "blockUp", "Direction",
        "TurnDelta", "SpeedWalk", "SpeedRun", "fSpeedMin", "fEquipWeapAdj", "fIdleTimer",
        "fMinSpeed", "fTwistDirection", "TurnDeltaDamped", "TurnMin", "Pitch", "PitchLook",
        "attackPowerStartTime", "PitchDefault", "PitchOverride", "staggerMagnitude",
        "recoilMagnitude", "SpeedSampled", "attackComboStartFraction", "attackIntroLength",
        "TimeDelta", "PitchOffset", "PitchAcc", "PitchThresh", "weapChangeStartFraction",
        "RotMax", "1stPRot", "1stPRotDamped", "PitchManualOverride", "SpeedAcc"
    ]

    /// Members a node computes and copies back to its bound variable.
    public static let outputMembers: Set = [
        "BSIsActiveModifier.bIsActive0", "BSIsActiveModifier.bIsActive1",
        "BSIsActiveModifier.bIsActive2", "BSIsActiveModifier.bIsActive3",
        "BSIsActiveModifier.bIsActive4", "BSInterpValueModifier.result",
        "hkbDampingModifier.dampedValue", "hkbDampingModifier.dampedVector",
        "BSSpeedSamplerModifier.speedOut", "BSDecomposeVectorModifier.x",
        "BSDecomposeVectorModifier.y", "BSDecomposeVectorModifier.z",
        "BSDecomposeVectorModifier.w", "BSGetTimeStepModifier.timeStep",
        "hkbTransformVectorModifier.vectorOut", "BSIStateManagerModifier.iStateVar",
        "BSDirectAtModifier.active", "BSDirectAtModifier.currentHeadingOffset",
        "BSDirectAtModifier.currentPitchOffset", "BSLookAtModifier.targetOutsideLimits",
        "hkbFootIkControlsModifier.errorOutTranslation", "hkbStateMachine.isActive",
        "hkbStateMachine.currentStateId", HKXGapCensus.syncUse
    ]

    /// Members that take a world position or rotation, which only the engine knows.
    public static let worldInputMembers: Set = [
        "BSLookAtModifier.targetLocation", "BSLookAtModifier.lookAtCameraX",
        "BSLookAtModifier.lookAtCameraY", "BSLookAtModifier.lookAtCameraZ",
        "BSDirectAtModifier.targetLocation", "BSDirectAtModifier.directAtCameraX",
        "BSDirectAtModifier.directAtCameraY", "BSDirectAtModifier.directAtCameraZ",
        "BSPassByTargetTriggerModifier.targetPosition", "BSTweenerModifier.targetPosition",
        "BSTweenerModifier.targetRotation"
    ]

    private static let engineVariablesLowercased = Set(engineVariables.map { $0.lowercased() })

    /// True when the engine must set or read `name`: the game exposes it, or a
    /// graph binds it to a world-space input. `uses` are `Class.member` paths.
    public static func isEngineFacing(_ name: String, uses: Set<String>) -> Bool {
        engineVariablesLowercased.contains(name.lowercased()) || !uses
            .isDisjoint(with: worldInputMembers)
    }

    /// True when a node of the graph computes `name` itself.
    public static func isGraphWritten(uses: Set<String>, assignedUse: String) -> Bool {
        uses.contains(assignedUse) || !uses.isDisjoint(with: outputMembers)
    }
}

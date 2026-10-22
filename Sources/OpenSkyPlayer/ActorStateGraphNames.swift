// The actor-state variables the engine shares with the player's behavior graphs: the
// inputs it writes each step, the outputs the graph publishes, and the `iState_*`
// constants that encode `iState`. Names and directions come from the install's
// character graphs, not memory (docs/engine/actor-state-graph.md).

import Foundation

nonisolated public enum ActorStateGraphNames: Sendable {
    // MARK: - Inputs the engine writes

    /// `BSLookAtModifier.lookAtTarget` in `0_master.hkx`. Bool.
    public static let headTracking = "bHeadTracking"
    /// `BSLookAtModifier.targetLocation`, world space. Quad.
    public static let targetLocation = "TargetLocation"
    /// The camera position the look and aim modifiers turn towards. Real.
    public static let cameraFromX = "camerafromx"
    public static let cameraFromY = "camerafromy"
    public static let cameraFromZ = "camerafromz"
    /// The spine twist of the bow aim in `1hm_behavior.hkx`, radians. Real.
    public static let pitch = "Pitch"
    /// The sprint transitions test `bSprintOK == 1`. Bool.
    public static let sprintOK = "bSprintOK"
    /// The block key: block with a shield or weapon, zoom with a bow. Int32 0 or 1.
    public static let wantBlock = "iWantBlock"
    /// A cast is wanted in that hand; `BSEventOnFalseToTrueModifier` starts it. Bool.
    public static let wantCastLeft = "bWantCastLeft"
    public static let wantCastRight = "bWantCastRight"
    /// A shout is wanted; `0_master.hkx` turns the rise into `BeginCastVoice`. Bool.
    public static let wantCastVoice = "bWantCastVoice"
    /// 1 while a hand casts, else 0. Real.
    public static let inCastState = "IsInCastState"
    /// The actor's state, as the value of one `iState_*` constant. Int32.
    public static let state = "iState"
    /// 1 while a weapon is drawn: the riding graph's combat idle (MountGraphNames.swift).
    public static let combatStance = MountGraphNames.combatStance

    /// Every input, in write order.
    public static let inputs = [
        headTracking, targetLocation, cameraFromX, cameraFromY, cameraFromZ, pitch,
        sprintOK, wantBlock, wantCastLeft, wantCastRight, wantCastVoice, inCastState,
        combatStance, state
    ]

    // MARK: - Outputs the graph publishes

    /// Bound to `BSIsActiveModifier`, `hkbStateMachine.isActive` or
    /// `currentStateId`, a sync variable, or an expression assignment.
    public static let outputs = [
        "bAnimationDriven", "bMotionDriven", "bAllowRotation", "bInMoveState", "bIsSynced",
        "bEquipOK", "bEquipUnequip", "IsEquipping", "IsUnequipping", "iEquippedItemState",
        "IsBashing", "IsRecoiling", "IsBlockHit", "iBlockState", "bNoStagger", "IsBleedingOut",
        "bLeftHandAttack", "iRegularAttack",
        "IsCastingLeft", "IsCastingRight", "IsCastingDual", "bMLh_Ready", "bMRh_Ready",
        "IsShouting", "bVoiceReady", "bRitualSpellActive",
        "bHeadTrackSpine", "PitchOverride", "PitchManualOverride", "1stPRot", "1stPRotDamped",
        "iSyncIdleLocomotion", "iSyncIdleState", "iSyncTurnState", "iSyncSprintState",
        "TurnDeltaDamped", "bIsInMT", "bIsRiding", "bAttached", "bTalkable",
        "bHumanoidFootIKEnable", "bHumanoidFootIKDisable", "bodyMorphWeight", "iDrunkVariable"
    ]
}

/// One value of `iState`. Each case names the `iState_*` constant in `0_master.hkx`
/// whose value the engine writes; the graph holds the numbers.
nonisolated public enum ActorGraphState: String, CaseIterable, Equatable, Sendable {
    case npcDefault = "iState_NPCDefault"
    case npcSprinting = "iState_NPCSprinting"
    case npcSneaking = "iState_NPCSneaking"
    case npcBowDrawn = "iState_NPCBowDrawn"
    case npcBowDrawnQuickShot = "iState_NPCBowDrawnQuickShot"
    case npcBlocking = "iState_NPCBlocking"
    case npcBlockingShieldCharge = "iState_NPCBlockingShieldCharge"
    case npcBleedout = "iState_NPCBleedout"
    case npc1HM = "iState_NPC1HM"
    case npc2HM = "iState_NPC2HM"
    case npcBow = "iState_NPCBow"
    case npcMagic = "iState_NPCMagic"
    case npcMagicCasting = "iState_NPCMagicCasting"
    case npcHorse = "iState_NPCHorse"
    case horseSprint = "iState_HorseSprint"
    case npcAttacking = "iState_NPCAttacking"
    case npcAttacking2H = "iState_NPCAttacking2H"
    case npcPowerAttacking = "iState_NPCPowerAttacking"
    case npcDrunk = "iState_NPCDrunk"

    public var variableName: String {
        rawValue
    }

    /// The readout name: the constant without its `iState_` prefix.
    public var displayName: String {
        String(rawValue.dropFirst("iState_".count))
    }
}

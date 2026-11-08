// Clip events the game takes no action on, as observed in the reference game. Nothing
// in OpenSky needs to react to them (docs/engine/animation-events.md#events-the-game-ignores).

import Foundation

nonisolated public enum IgnoredAnimationEvents: Sendable {
    /// Compared without case, like `AnimationEventAction.handledEvents`.
    public static let names = [
        "StartAnimationDriven", "Open",
        "SyncLeft", "SyncRight", "SyncPoint", "SyncRun", "SyncB_Right", "SyncF_Left",
        "BenthicAOE", "NPCDogDeathHoundAggroWarning", "NPCDogIdleSniff",
        "NPCScribAmbushDigIn", "NPCScribAmbushDigOut", "NPCScribAttack1", "NPCScribAttack2",
        "NPCScribAttackBash", "NPCScribAttackForward", "NPCScribAttackForwardLarge",
        "NPCScribAttackForwardStance", "NPCScribIdle2", "NPCScribIdle3CleanFace",
        "L1_Start", "L1_Stop", "R1_Start", "R1_Stop"
    ]
}

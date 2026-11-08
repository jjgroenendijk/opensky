import Foundation

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

    /// The states only the graph enters, from a perk's graph flag
    /// (docs/engine/actor-state-graph.md).
    public static let perkStates: [ActorGraphState] = [
        .npcBowDrawnQuickShot,
        .npcBlockingShieldCharge
    ]

    /// The readout name: the constant without its `iState_` prefix.
    public var displayName: String {
        String(rawValue.dropFirst("iState_".count))
    }
}

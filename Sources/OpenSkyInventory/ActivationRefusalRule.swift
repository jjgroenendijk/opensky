// Use-key presses the game refuses with a notice: an actor that cannot talk, a busy
// or used piece of furniture, a parent-activated object, and use during combat. The
// texts are string settings. See docs/engine/interaction.md#refused-activations.

import OpenSkyGameData
import OpenSkyWorldInterface

nonisolated public enum ActivationRefusalText: String, GameSettingTextKey {
    case creatureCalmed = "sActivateCreatureCalmed"
    /// Follows the actor's name.
    case personCalmed = "sActivateNPCCalmed"
    /// Follows the actor's name.
    case fleeing = "sNoTalkFleeing"
    /// Follows the actor's name.
    case unconscious = "sNoTalkUnConscious"
    case inScene = "sSceneBlockingActorActivation"
    case objectInUse = "sObjectInUse"
    case usedBySomeoneElse = "sFailedActivation"
    case remoteActivation = "sRemoteActivation"
    case combat = "sCombatCannotActivate"
    case child = "sNoChildUse"

    public var fallback: String {
        switch self {
        case .creatureCalmed: "The creature is calmed and cannot respond."
        case .personCalmed: "is calmed and cannot respond."
        case .fleeing: " is fleeing for their life."
        case .unconscious: " is unconscious."
        case .inScene: "This person is busy."
        case .objectInUse: "This object is already in use by someone else."
        case .usedBySomeoneElse: "Someone else is using this."
        case .remoteActivation: "This object is activated from somewhere else."
        case .combat: "You cannot use this while in combat."
        case .child: "Children cannot use that."
        }
    }
}

/// What the gate knows about the target and the player when the use key goes down.
nonisolated public struct ActivationFacts: Equatable, Sendable {
    public var action: InteractionAction
    /// The target's actor state. Nil for an object.
    public var actor: ActorActivationState?
    public var isFurniture = false
    /// Another actor sits in or uses the furniture.
    public var furnitureOccupied = false
    /// Another actor walks to the furniture to use it.
    public var furnitureReserved = false
    /// `XAPD` Parent Activate Only: only the activate parent opens it.
    public var parentActivateOnly = false
    /// The target refuses use in combat, such as a crafting station.
    public var blocksInCombat = false
    public var playerInCombat = false
    public var playerIsChild = false

    public init(action: InteractionAction) {
        self.action = action
    }
}

nonisolated public struct ActorActivationState: Equatable, Sendable {
    public var name: String
    public var isCreature = false
    public var isCalmed = false
    public var isFleeing = false
    public var isUnconscious = false
    public var isInScene = false

    public init(name: String) {
        self.name = name
    }
}

nonisolated public enum ActivationRefusalRule {
    /// The notice of a refused press, or nil to let it through. OpenSky's reading of the
    /// order: the target's own state first, then the player's.
    public static func refusal(
        _ facts: ActivationFacts, texts: GameSettingTexts<ActivationRefusalText>
    ) -> String? {
        if facts.parentActivateOnly {
            return texts[.remoteActivation]
        }
        if let actor = facts.actor, facts.action == .talk, let text = refusal(actor, texts) {
            return text
        }
        if facts.furnitureOccupied {
            return texts[.objectInUse]
        }
        if facts.furnitureReserved {
            return texts[.usedBySomeoneElse]
        }
        if facts.blocksInCombat, facts.playerInCombat {
            return texts[.combat]
        }
        if facts.playerIsChild, facts.isFurniture {
            return texts[.child]
        }
        return nil
    }

    private static func refusal(
        _ actor: ActorActivationState, _ texts: GameSettingTexts<ActivationRefusalText>
    ) -> String? {
        if actor.isUnconscious {
            return actor.name + texts[.unconscious]
        }
        if actor.isCalmed {
            return actor.isCreature
                ? texts[.creatureCalmed] : "\(actor.name) \(texts[.personCalmed])"
        }
        if actor.isFleeing {
            return actor.name + texts[.fleeing]
        }
        return actor.isInScene ? texts[.inScene] : nil
    }
}

// App side of the refused activations that show a notice: it gathers the target's
// and the player's state for `ActivationRefusalRule` and shows the text it returns.
// See docs/engine/interaction.md#refused-activations.

import OpenSkyActorsInterface
import OpenSkyAIPackages
import OpenSkyCombatInterface
import OpenSkyDialogueInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyMagicInterface
import OpenSkyMenusInterface
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState

/// What `ActivationRefusalWorldAdapter` reads from the session.
@MainActor
public protocol ActivationRefusalWorldHost: AnyObject {
    var actorValues: any ActorValuePort { get }
    var actorWorld: any ActorWorldPort { get }
    var combat: any CombatPort { get }
    var furniture: any FurniturePort { get }
    var hud: any HUDPort { get }
    var magic: any MagicPort { get }
    var magicWorld: any MagicWorldPort { get }
    var mapWorld: any MapWorldPort { get }
    var ragdollWorld: any RagdollWorldPort { get }
    var scenes: any ScenePort { get }
    var scripts: any ScriptPort { get }
    var streamer: (any CellStreamerPort)? { get }
}

public final class ActivationRefusalWorldAdapter {
    public let game: any ActivationRefusalWorldHost

    public init(game: any ActivationRefusalWorldHost) {
        self.game = game
    }

    func facts(for target: InteractionTarget) -> ActivationFacts {
        let interaction = target.interaction
        var facts = ActivationFacts(action: interaction.action)
        facts.parentActivateOnly = interaction.parentActivateOnly
        facts.isFurniture = !interaction.seats.isEmpty
        facts.blocksInCombat = interaction.station != nil || interaction.isBed
        facts.playerInCombat = facts.blocksInCombat && game.actorWorld.isInCombat(.player)
        facts.playerIsChild = game.actorValues.runtime?.baseline(of: .player).isChild == true
        guard let key = game.streamer?.referenceEntry(formID: interaction.reference)?.key else {
            return facts
        }
        if interaction.action == .talk {
            facts.actor = actorState(of: key, name: interaction.name)
        }
        if !interaction.seats.isEmpty {
            let holders = game.furniture.ledger.holders(of: key).values.filter { $0 != .player }
            let free = interaction.seats.filter(\.isEnabled).count - holders.count
            if free <= 0, !holders.isEmpty {
                let seated = holders.contains { game.furniture.occupancies[$0] != nil }
                facts.furnitureOccupied = seated
                facts.furnitureReserved = !seated
            }
        }
        return facts
    }

    private func actorState(of key: ReferenceKey, name: String) -> ActorActivationState {
        var state = ActorActivationState(name: name)
        if let holder = game.ragdollWorld.holder(of: key) {
            state.isCreature = !game.magicWorld.actorHasKeyword("ActorTypeNPC", on: holder)
        }
        state.isCalmed = game.magic.influence(of: key).isCalmed
        state.isFleeing = game.combat.loop?.actionFacts(of: key)?.isFleeing == true
        state.isUnconscious = game.scripts.bridge?.scriptedState(of: key)
            .flag(ScriptedStateName.unconscious) == true
        state.isInScene = game.scenes.actorsInScenes().contains(key)
        return state
    }
}

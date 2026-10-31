// App side of the refused activations that show a notice: it gathers the target's
// and the player's state for `ActivationRefusalRule` and shows the text it returns.
// See docs/engine/interaction.md#refused-activations.

import OpenSkyActors
import OpenSkyActorsInterface
import OpenSkyAIPackages
import OpenSkyCombat
import OpenSkyDialogue
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyMagic
import OpenSkyMagicInterface
import OpenSkyMenus
import OpenSkyScripting
import OpenSkyScriptingInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState

/// What `ActivationRefusalWorldAdapter` reads from the session.
@MainActor
protocol ActivationRefusalWorldHost: AnyObject {
    var actorValues: ActorValueCoordinator { get }
    var actorWorld: ActorWorldAdapter { get }
    var combat: CombatCoordinator { get }
    var furniture: FurnitureCoordinator { get }
    var hud: HUDCoordinator { get }
    var magic: MagicCoordinator { get }
    var magicWorld: MagicWorldAdapter { get }
    var mapWorld: MapWorldAdapter { get }
    var ragdollWorld: RagdollWorldAdapter { get }
    var scenes: SceneCoordinator { get }
    var scripts: ScriptCoordinator { get }
    var streamer: CellStreamer? { get }
}

final class ActivationRefusalWorldAdapter {
    unowned let game: any ActivationRefusalWorldHost

    init(game: any ActivationRefusalWorldHost) {
        self.game = game
    }

    func wire() {
        guard let streamer = game.streamer else { return }
        streamer.activationGate.register(.notice) { [weak self] target in
            guard let self else { return nil }
            let texts = game.mapWorld.settingTexts(ActivationRefusalText.self)
            return ActivationRefusalRule.refusal(facts(for: target), texts: texts).map {
                .notice($0)
            }
        }
        streamer.activationGate.refusals.register(.notice) { [weak self] event in
            guard let self, case let .notice(text) = event.refusal else { return }
            game.hud.showNotification(text)
        }
    }

    private func facts(for target: InteractionTarget) -> ActivationFacts {
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
        state.isFleeing = game.combat.loop?.phase(of: key)?.actionFacts.isFleeing == true
        state.isUnconscious = game.scripts.bridge?.scriptedState(of: key)
            .flag(ScriptedStateName.unconscious) == true
        state.isInScene = game.scenes.actorsInScenes().contains(key)
        return state
    }
}

// The live seams every condition context carries besides the feature ones:
// script variables, scenes, weather, and the player's inventory.

import Foundation
import OpenSkyActorsInterface
import OpenSkyConditions
import OpenSkyDialogue
import OpenSkyDialogueInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyPhysics
import OpenSkyQuestsInterface
import OpenSkyScripting
import OpenSkyWorld

extension RuntimeStateWorldAdapter {
    func addLiveSeams(to context: inout ConditionContext) {
        context.scriptVariables = game.scripts.runtime?.scriptVariableResolution() ?? .empty
        context.scenes = game.scenes.conditionResolution(aliases: context.aliases)
        context.weather = weatherResolution()
        if let inventory = playerInventoryResolution() {
            context.inventory = inventory
        }
    }

    private func weatherResolution() -> WeatherConditionResolution {
        guard
            let weather = game.renderer?.weather,
            let current = weather.currentWeatherID
        else { return .empty }
        return WeatherConditionResolution(
            weather: current,
            precipitation: weather.store.weather(current)?.data?.precipitation ?? .none
        )
    }

    /// The player's item counts and equipped items. Other holders are not read yet.
    private func playerInventoryResolution() -> InventoryConditionResolution? {
        guard let runtime = game.inventory.runtime else { return nil }
        let stacks = runtime.inventory.inventory(of: runtime.player).stacks
        let equipped = game.inventory.equipment?.equipped(on: runtime.player) ?? []
        return InventoryConditionResolution(
            counts: [.player: stacks.reduce(into: [:]) { $0[$1.item, default: 0] += $1.count }],
            equipped: [.player: Set(equipped)]
        )
    }

    /// The player's sex and race from the race menu, and the gait the walk uses.
    func playerConditionTraits(_ state: inout ActorConditionState) {
        if let identity = game.menuWorld.playerIdentity {
            state.isFemale = identity.isFemale
            state.race = identity.race
        }
        state.isSneaking = game.renderer.map { $0.locomotion.status.gait == .sneak }
    }
}

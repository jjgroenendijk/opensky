// `CombatWorldAdapter` joins the started session: what `wireLoop` registered.

import OpenSkyActorPresentation
import OpenSkyActors
import OpenSkyActorsInterface
import OpenSkyAIPackages
import OpenSkyBehavior
import OpenSkyCamera
import OpenSkyCells
import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyCrime
import OpenSkyDialogue
import OpenSkyDialogueInterface
import OpenSkyEffects
import OpenSkyFactions
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyMagic
import OpenSkyMagicInterface
import OpenSkyMenus
import OpenSkyPerception
import OpenSkyPlayer
import OpenSkyProgression
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyScripting
import OpenSkySessionInterface
public import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState

/// Wired after melee, archery and the ragdolls, so the loop steps last.
public struct CombatLoopWiring {
    public init(_ adapter: CombatWorldAdapter, gameSession: GameSession) {
        let combat = adapter.game.combat
        let store = adapter.game.playerSettingsStore
        combat.load(settings: store)
        // The launcher page writes the switch while a session runs.
        store.observe { [weak combat, weak store] id in
            guard id == .combatTemperament || id == .combatGameSettings, let store else { return }
            combat?.load(settings: store)
        }
        gameSession.worldTick.register(.combatLoop) { [weak combat, weak adapter] delta in
            adapter?.run(combat?.advanceLoop(by: delta) ?? [])
            adapter?.updateNPCDrawStates()
        }
    }
}

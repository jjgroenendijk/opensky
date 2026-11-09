// `CombatWorldAdapter` joins the started session: what `wireLoop` registered.

import OpenSkyActorPresentation
import OpenSkyActorsInterface
import OpenSkyAIPackages
import OpenSkyBehavior
import OpenSkyCamera
import OpenSkyCells
import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyCrimeInterface
import OpenSkyDialogueInterface
import OpenSkyEffects
import OpenSkyFactionsInterface
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyMenusInterface
import OpenSkyPerceptionInterface
import OpenSkyPlayer
import OpenSkyProgressionInterface
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyScriptingInterface
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

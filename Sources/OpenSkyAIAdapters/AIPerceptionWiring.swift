// `AIPerceptionSenseAdapter` joins the started session: what `wirePerception` registered.

import OpenSkyActorPresentation
import OpenSkyActors
import OpenSkyActorsInterface
import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyCrime
import OpenSkyDiagnostics
import OpenSkyDialogue
import OpenSkyFactions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyMagic
import OpenSkyNavigation
import OpenSkyPerception
import OpenSkyPerceptionInterface
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyProgression
import OpenSkyProgressionInterface
import OpenSkyQuestsInterface
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyScripting
import OpenSkyScriptingInterface
import OpenSkySessionInterface
public import OpenSkyWorld
import OpenSkyWorldConditions
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// Runs after NPC movement and the combat loop, because the pass reads
/// where actors ended up this frame and which of them are hostile.
public struct AIPerceptionWiring {
    public init(_ adapter: AIPerceptionSenseAdapter, gameSession: GameSession) {
        let renderer = gameSession.renderer
        let perception = adapter.game.perception
        gameSession.worldTick.register(.perception) { [weak owner = adapter.owner] delta in
            guard owner != nil else { return }
            adapter.run(adapter.game.perception.advance(by: delta))
            // After the pass, so a trespass is judged against this frame's detection.
            adapter.game.crime.advanceTrespass(by: Double(delta))
            adapter.game.crime.advanceFavour()
            adapter.game.crime.advanceReports()
            adapter.game.crime.advanceJail()
            // After the trespass, so the guards see a bounty charged this frame.
            adapter.game.crimeWorld.run(adapter.game.crime.advanceGuardResponse())
        }
        renderer.worldOverlaySources
            .register(identifier: "detection") { [weak perception] context, list in
                perception?.appendWorldOverlay(context: context, to: &list)
            }
    }
}

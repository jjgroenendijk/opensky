// `AIPerceptionSenseAdapter` joins the started session: what `wirePerception` registered.

import OpenSkyActorPresentation
import OpenSkyActorsInterface
import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyCrimeInterface
import OpenSkyDialogueInterface
import OpenSkyFactionsInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyNavigation
import OpenSkyPerceptionInterface
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyProgressionInterface
import OpenSkyQuestsInterface
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRuntimeState
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
    public init(_ owner: AIWorldAdapter, gameSession: GameSession) {
        let renderer = gameSession.renderer
        let perception = owner.perceptionSense.game.perception
        gameSession.worldTick.register(.perception) { [weak owner] delta in
            guard let adapter = owner?.perceptionSense else { return }
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

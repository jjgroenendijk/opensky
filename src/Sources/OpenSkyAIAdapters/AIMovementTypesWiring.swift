// `AIWorldAdapter` joins the started session: what `wireMovementTypes` registered.

import OpenSkyActorPresentation
import OpenSkyCells
import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyGameData
import OpenSkySessionInterface
public import OpenSkyWorld
import simd

/// The speeds of the movement type the actor's graph state names.
public struct AIMovementTypesWiring {
    public init(_ adapter: AIWorldAdapter, streamer: CellStreamer) {
        streamer.npcMovementSpeeds = { [weak game = adapter.game] actor in
            guard
                let game, let name = game.actorGraphWorld.graphs.movementStateName(of: actor)
            else { return nil }
            return game.worldData?.movementTypes.type(named: name)?.speeds
        }
    }
}

// What an NPC mover reads per actor: the skeleton bound it sizes a long body from
// (docs/engine/character-shapes.md), loaded off the main actor, and its movement type.

import OpenSkyActorPresentation
import OpenSkyCells
import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyGameData
import OpenSkySessionInterface
public import OpenSkyWorld
import simd

extension AIWorldAdapter {
    public func wireBodyShapes(streamer: CellStreamer) {
        guard let fileSystem = game.worldData?.scriptFileSystem else { return }
        let bounds = AssetLoader<String, SIMD3<Float>> { path in
            let file = try NIFFile(data: fileSystem.contents(forPath: path))
            for case let .bound(_, halfExtents) in file.rootExtraData.map(\.value) {
                return halfExtents
            }
            throw AssetLoadFailure(reason: "\(path) has no BBX bound")
        }
        streamer.npcBodyHalfExtents = { [weak game] actor in
            guard let skeleton = game?.effectsWorld.race(of: actor)?.maleSkeletonPath else {
                return nil
            }
            _ = bounds.drain()
            return bounds.value(for: ActorGraphCore.projectPath(modelPath: skeleton))
        }
    }

    /// The speeds of the movement type the actor's graph state names.
    public func wireMovementTypes(streamer: CellStreamer) {
        streamer.npcMovementSpeeds = { [weak game] actor in
            guard
                let game, let name = game.actorGraphWorld.graphs.movementStateName(of: actor)
            else { return nil }
            return game.worldData?.movementTypes.type(named: name)?.speeds
        }
    }
}

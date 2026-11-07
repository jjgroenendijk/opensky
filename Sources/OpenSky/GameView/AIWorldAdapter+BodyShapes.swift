// The skeleton bound an NPC mover sizes a long body from (docs/engine/character-shapes.md).
// It loads off the main actor; a mover that starts before it is ready walks upright.

import OpenSkyActorPresentation
import OpenSkyCells
import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyGameData
import OpenSkyWorld
import simd

extension AIWorldAdapter {
    func wireBodyShapes(streamer: CellStreamer) {
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
}

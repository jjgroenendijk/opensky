// `AIWorldAdapter` joins the started session: what `wireBodyShapes` registered.

import OpenSkyActorPresentation
import OpenSkyCells
import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyGameData
import OpenSkySessionInterface
public import OpenSkyWorld
import OpenSkyWorldInterface
import simd

/// Connects `AIWorldAdapter` to the started session.
public struct AIBodyShapesWiring {
    public init(_ adapter: AIWorldAdapter, streamer: CellStreamer) {
        guard let fileSystem = adapter.game.worldData?.scriptFileSystem else { return }
        let bounds = AssetLoader<String, SIMD3<Float>> { path in
            let file = try NIFFile(data: fileSystem.contents(forPath: path))
            for case let .bound(_, halfExtents) in file.rootExtraData.map(\.value) {
                return halfExtents
            }
            throw AssetLoadFailure(reason: "\(path) has no BBX bound")
        }
        streamer.npcBodyHalfExtents = { [weak game = adapter.game] actor in
            guard let skeleton = game?.effectsWorld.race(of: actor)?.maleSkeletonPath else {
                return nil
            }
            _ = bounds.drain()
            return bounds.value(for: ActorGraphCore.projectPath(modelPath: skeleton))
        }
    }
}

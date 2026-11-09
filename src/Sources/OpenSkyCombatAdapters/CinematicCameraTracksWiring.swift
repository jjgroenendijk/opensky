// `CinematicCameraWorldAdapter` joins the started session: what `wireTracks` registered.

import Foundation
import OpenSkyActorsInterface
import OpenSkyCamera
import OpenSkyCells
import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyEffects
import OpenSkyFactionsInterface
import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyGameData
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkySessionInterface
public import OpenSkyWorld
import OpenSkyWorldInterface
import simd

/// A shot whose track has not arrived plays without one, as a shot with no model does.
public struct CinematicCameraTracksWiring {
    public init(_ adapter: CinematicCameraWorldAdapter, gameSession: GameSession) {
        guard let files = adapter.game.worldData?.scriptFileSystem else {
            return
        }
        let tracks = AssetLoader<String, NIFCameraTrack> { model in
            try NIFCameraTrack(file: NIFFile(data: files.contents(forPath: "meshes\\" + model)))
        }
        for shot in adapter.cameraPaths?.shots.records ?? [] {
            if let model = shot.record.model?.path {
                tracks.prefetch(model)
            }
        }
        adapter.tracks = tracks
        gameSession.assetDrains.register(.cinematicTracks) { _ in tracks.drain() }
    }
}

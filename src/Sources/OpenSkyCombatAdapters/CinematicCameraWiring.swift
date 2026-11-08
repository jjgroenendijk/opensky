// `CinematicCameraWorldAdapter` joins the started session: what `wire` registered.

import Foundation
import OpenSkyActorsInterface
import OpenSkyCamera
import OpenSkyCells
import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyEffects
import OpenSkyFactions
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

/// Connects `CinematicCameraWorldAdapter` to the started session.
public struct CinematicCameraWiring {
    public init(_ adapter: CinematicCameraWorldAdapter, gameSession: GameSession) {
        _ = CinematicCameraTracksWiring(adapter, gameSession: gameSession)
        // Frame steps run under a menu too; the shot keeps real time, so a
        // paused frame advances nothing.
        gameSession.frameSteps.register(.cinematicCamera) { [weak adapter, weak gameSession] _ in
            guard let adapter, let gameSession else { return }
            let now = Date()
            let seconds = gameSession.worldSimPaused ? 0 : adapter.lastFrame
                .map { now.timeIntervalSince($0) } ?? 0
            adapter.lastFrame = now
            adapter.apply(adapter.game.cinematicCamera.tick(realSeconds: min(
                seconds,
                CinematicCameraCoordinator.longestFrameSeconds
            )))
        }
    }
}

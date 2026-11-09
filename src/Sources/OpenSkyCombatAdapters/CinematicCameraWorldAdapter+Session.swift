// `CinematicCameraWorldAdapter` built over the started session: it registers its frame steps and
// session events as it is built (docs/decisions/session-scope.md).

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

extension CinematicCameraWorldAdapter {
    /// Without a stage, as in a test, it registers nothing.
    public convenience init(game: any CinematicCameraWorldHost, stage: SessionStage?) {
        self.init(game: game)
        guard let stage else { return }
        registerCinematicCamera(stage: stage)
    }

    private func registerCinematicCameraTracks(stage: SessionStage) {
        let gameSession = stage.gameSession
        guard let files = game.worldData?.scriptFileSystem else {
            return
        }
        let tracks = AssetLoader<String, NIFCameraTrack> { model in
            try NIFCameraTrack(file: NIFFile(data: files.contents(forPath: "meshes\\" + model)))
        }
        for shot in cameraPaths?.shots.records ?? [] {
            if let model = shot.record.model?.path {
                tracks.prefetch(model)
            }
        }
        self.tracks = tracks
        gameSession.assetDrains.register(.cinematicTracks) { _ in tracks.drain() }
    }

    private func registerCinematicCamera(stage: SessionStage) {
        let gameSession = stage.gameSession
        registerCinematicCameraTracks(stage: stage)
        // Frame steps run under a menu too; the shot keeps real time, so a
        // paused frame advances nothing.
        gameSession.frameSteps.register(.cinematicCamera) { [weak self, weak gameSession] _ in
            guard let self, let gameSession else { return }
            let now = Date()
            let seconds = gameSession.worldSimPaused ? 0 : lastFrame
                .map { now.timeIntervalSince($0) } ?? 0
            lastFrame = now
            apply(game.cinematicCamera.tick(realSeconds: min(
                seconds,
                CinematicCameraCoordinator.longestFrameSeconds
            )))
        }
    }
}

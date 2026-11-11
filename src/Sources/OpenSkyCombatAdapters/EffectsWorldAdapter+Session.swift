// `EffectsWorldAdapter` built over the started session: it registers its frame steps and
// session events as it is built (docs/decisions/session-scope.md).

public import Foundation
import OpenSkyActorPresentation
import OpenSkyActorsInterface
import OpenSkyCells
import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyEffects
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface
import OpenSkyMenusInterface
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRenderResources
import OpenSkyScriptingInterface
import OpenSkySessionInterface
public import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

extension EffectsWorldAdapter {
    /// Without a stage, as in a test, it registers nothing.
    public convenience init(
        game: some EffectsWorldHost & EffectsBodyImpulsesHost & EffectsTrapControlHost &
            EffectsBlastsHost & EffectsEffectPlacementHost & EffectsLocatorHost,
        stage: SessionStage?,
        now: @escaping () -> Date
    ) {
        self.init(game: game, now: now)
        guard let stage else { return }
        registerEffects(stage: stage)
    }

    private func registerEffects(stage: SessionStage) {
        let provider = stage.data
        let streamer = stage.streamer
        let gameSession = stage.gameSession
        guard let records = provider.effectRecords else { return }
        gameSession.imageSpaceLinks = ImageSpaceLinks(
            records: records, weatherPlugin: EffectsBasePlugin.name
        )
        let frameSteps = gameSession.frameSteps
        frameSteps.register(.effects) { [weak self, weak gameSession, weak streamer] position in
            guard let self, let gameSession else { return }
            state.cameraPosition = position
            let now = now()
            let renderer = gameSession.renderer
            gameSession.imageSpaceLinks?.interior = streamer?.interiorScene.map {
                InteriorImageSpace(imageSpace: $0.imageSpace, plugin: EffectsBasePlugin.name)
            }
            let paused = gameSession.worldSimPaused
            let elapsed = lastFrame.map { Float(now.timeIntervalSince($0)) } ?? 0
            let seconds = paused ? 0 : min(elapsed, Self.longestStep)
            lastFrame = paused ? nil : now
            frameLooks.attachRaceEffects()
            explosions.advance(seconds)
            effectPlacement.stepHealthCues(seconds, gameSession: gameSession)
            do {
                try effects.step(seconds, extraModels: frameLooks.extraModels(), renderer: renderer)
            } catch {
                Self.logger.error(
                    "[ERROR] effect draw lists: \(String(describing: error), privacy: .public)"
                )
            }
            let uptime = now.timeIntervalSinceReferenceDate
            let delta = Float(uptime - (state.lastImpulseStep ?? uptime))
            state.lastImpulseStep = uptime
            if gameSession.movementMode.isPlayerControlled {
                game.combat.impulses?.advance(deltaTime: delta)
            }
        }
    }
}

extension EffectsWorldAdapter {
    private static let logger = EngineLogger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "Effects"
    )
}

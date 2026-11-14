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
        game: some EffectsWorldHosts,
        stage: SessionStage?,
        now: @escaping () -> Date
    ) {
        self.init(game: game, now: now)
        guard let stage else { return }
        frames.registerEffects(stage: stage)
    }
}

extension EffectsFrameStep {
    func registerEffects(stage: SessionStage) {
        let provider = stage.data
        let streamer = stage.streamer
        let gameSession = stage.gameSession
        guard let records = provider.effectRecords else { return }
        gameSession.sky.imageSpaceLinks = ImageSpaceLinks(
            records: records, weatherPlugin: FormIDResolver.loadOrderSpaceName
        )
        let frameSteps = gameSession.frameSteps
        frameSteps.register(.effects) { [weak self, weak gameSession, weak streamer] position in
            guard let self, let gameSession else { return }
            state.cameraPosition = position
            let now = now()
            let renderer = gameSession.renderer
            gameSession.sky.imageSpaceLinks?.interior = streamer?.interiorScene.map {
                InteriorImageSpace(
                    imageSpace: $0.imageSpace, plugin: FormIDResolver.loadOrderSpaceName
                )
            }
            let paused = gameSession.worldSimPaused
            let elapsed = lastFrame.map { Float(now.timeIntervalSince($0)) } ?? 0
            let seconds = paused ? 0 : min(elapsed, Self.longestStep)
            lastFrame = paused ? nil : now
            frameLooks.attachRaceEffects()
            hosts.combat.explosions.advance(seconds)
            EffectsEffectPlacementAdapter(game: hosts, state: state).stepHealthCues(
                seconds,
                gameSession: gameSession
            )
            do {
                try hosts.effects.step(
                    seconds,
                    extraModels: frameLooks.extraModels(),
                    renderer: renderer
                )
            } catch {
                Self.logger.error(
                    "[ERROR] effect draw lists: \(String(describing: error), privacy: .public)"
                )
            }
            let uptime = now.timeIntervalSinceReferenceDate
            let delta = Float(uptime - (state.lastImpulseStep ?? uptime))
            state.lastImpulseStep = uptime
            if gameSession.movementMode.isPlayerControlled {
                hosts.combat.impulses?.advance(deltaTime: delta)
            }
        }
    }
}

extension EffectsFrameStep {
    private static let logger = EngineLogger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "Effects"
    )
}

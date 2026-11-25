// `AnimationEventWorldAdapter` built over the started session: it registers its frame steps and
// session events as it is built (docs/decisions/session-scope.md).

import Foundation
import OpenSkyActorPresentation
import OpenSkyCamera
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyObjectAnimation
import OpenSkyPlayer
import OpenSkyRenderCore
import OpenSkyScriptingInterface
import OpenSkySessionInterface
public import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

extension AnimationEventWorldAdapter {
    /// Without a stage, as in a test, it registers nothing.
    public convenience init(game: any AnimationEventWorldHost, stage: SessionStage?) {
        self.init(game: game)
        guard let stage else { return }
        PlayerAnimationEventStep(game: game).registerAnimationEvent(stage: stage)
    }
}

/// The frame step that hands the player's graph events to audio and scripts.
@MainActor
struct PlayerAnimationEventStep {
    let game: any AnimationEventWorldHost

    func registerAnimationEvent(stage: SessionStage) {
        let gameSession = stage.gameSession
        let game = game
        gameSession.frameSteps.register(.animationEvents) { [weak gameSession, weak game] _ in
            guard let gameSession else { return }
            let idles = game?.idleWorld.idles
            let events = gameSession.audio.animationEvents
            let locomotion = gameSession.locomotion
            // Read before the events below can end the pair.
            let killer = idles?.pairedAnimation(of: .player)
                .map { $0.lead == .player ? $0.partner : $0.lead }
            let names = locomotion.graphEvents.drain(locomotion.animationEventConsumer)
                .map { idles?.ownGraphEvent($0, from: .player) ?? $0 }
            // A kill move's victim half sends `2_KillActor`; the other actor of the pair is
            // the killer (docs/engine/paired-animations.md#the-player-as-the-victim).
            for name in names
                where name.caseInsensitiveCompare(IdleCore.killEvent) == .orderedSame
            {
                game?.scripts.bridge?.killActor(.player, killer: killer)
            }
            guard gameSession.movementMode.isPlayerControlled else { return }
            for name in names {
                events?.handle(name, from: .player)
            }
        }
    }
}

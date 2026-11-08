// `AnimationEventWorldAdapter` joins the started session: what `wire` registered.

import OpenSkyActorPresentation
import OpenSkyCamera
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyObjectAnimation
import OpenSkyPlayer
import OpenSkyRenderCore
import OpenSkyScripting
import OpenSkySessionInterface
public import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// The player graph's events, read once per frame. The idle and object graph
/// callbacks send theirs to the coordinator directly.
public struct AnimationEventWiring {
    public init(_ adapter: AnimationEventWorldAdapter, gameSession: GameSession) {
        let idles = adapter.game.idleWorld.idles
        gameSession.frameSteps.register(.animationEvents) { [weak gameSession, weak idles] _ in
            guard let gameSession else { return }
            let events = gameSession.animationEvents
            let locomotion = gameSession.locomotion
            let names = locomotion.graphEvents.drain(locomotion.animationEventConsumer)
                .map { idles?.ownGraphEvent($0, from: .player) ?? $0 }
            guard gameSession.movementMode.isPlayerControlled else { return }
            for name in names {
                events?.handle(name, from: .player)
            }
        }
    }
}

// App side of the effect graphs: hands the coordinator the live effects on actors,
// steps it in the world update, and sends an effect graph's events on as its actor's.
// The rules live in `EffectGraphCoordinator` (docs/engine/effect-graphs.md).

import OpenSkyActorPresentation
import OpenSkyEffects
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyObjectAnimation
import OpenSkyRendering
import OpenSkyWorld

/// What `EffectGraphWorldAdapter` reads from the session. `GameSessionScope` conforms.
@MainActor
protocol EffectGraphWorldHost: AnyObject {
    var effects: EffectsCoordinator { get set }
    var effectGraphs: EffectGraphCoordinator { get }
    var gameSession: GameSession? { get }
    var audioFileSystem: (any GameFileSource)? { get }
}

final class EffectGraphWorldAdapter {
    unowned let game: any EffectGraphWorldHost

    init(game: any EffectGraphWorldHost) {
        self.game = game
    }

    /// After the actor and object graphs, so the events they raised this frame reach
    /// the effect graphs in the same frame.
    func wire(gameSession: GameSession) {
        guard game.audioFileSystem != nil else { return }
        gameSession.worldTick.register(.effectGraphs) { [weak self] delta in
            self?.game.effectGraphs.tick(deltaTime: delta)
        }
    }
}

extension EffectGraphWorldAdapter: EffectGraphWorld {
    func attachedEffectModels() -> [AttachedEffectModel] {
        game.effects.visualEffects.instances.compactMap { instance in
            guard case let .actor(actor) = instance.anchor, let model = instance.spec.artModel
            else { return nil }
            return AttachedEffectModel(
                effectID: instance.id, actor: actor, effectName: instance.spec.name,
                modelPath: model
            )
        }
    }

    func effectGraphFired(_ event: String, from actor: ReferenceKey) {
        game.gameSession?.animationEvents?.handle(event, from: actor, reachesEffectGraphs: false)
    }
}

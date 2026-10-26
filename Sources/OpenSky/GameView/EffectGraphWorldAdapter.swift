// App side of the actor sub-graphs: hands the coordinator the live effects and the worn
// armour addons, steps it in the world update, and sends a sub-graph's events on as its
// actor's.
// The rules live in `EffectGraphCoordinator` (docs/engine/effect-graphs.md).

import OpenSkyActorPresentation
import OpenSkyBehavior
import OpenSkyCombat
import OpenSkyEffects
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyObjectAnimation
import OpenSkyPlayer
import OpenSkyRendering
import OpenSkyWorld

/// What `EffectGraphWorldAdapter` reads from the session. `GameSessionScope` conforms.
@MainActor
protocol EffectGraphWorldHost: AnyObject {
    var actorGraphs: ActorGraphCoordinator { get }
    var actorWorld: ActorWorldAdapter { get }
    var effects: EffectsCoordinator { get set }
    var effectGraphs: EffectGraphCoordinator { get }
    var gameSession: GameSession? { get }
    var audioFileSystem: (any GameFileSource)? { get }
    func actorPlayback(for key: ReferenceKey) -> ActorAnimationPlayback?
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
    func attachedSubGraphs() -> [AttachedSubGraph] {
        effectSubGraphs() + armorAddonSubGraphs()
    }

    func character(of actor: ReferenceKey) -> SubGraphCharacter? {
        let isPlayer = actor == .player
        let graph = isPlayer
            ? game.gameSession?.locomotion.graph : game.actorGraphs.instance(of: actor)
        if let graph {
            let pose = isPlayer ? game.gameSession?.locomotion.pose : game.actorGraphs
                .pose(of: actor)
            return SubGraphCharacter(
                context: graph.characterContext, variables: graph.variables,
                rig: pose.map { SubGraphActorRig(skeleton: graph.skeleton, pose: $0) }
            )
        }
        guard let observed = game.actorWorld.combatActor(key: actor) else { return nil }
        let context = BehaviorCharacterContext(
            worldPosition: observed.feet,
            worldRotation: ActorGraphCore.worldRotation(placementRotationZ: observed.facing)
        )
        return SubGraphCharacter(context: context, variables: nil)
    }

    func effectGraphFired(_ event: String, from actor: ReferenceKey) {
        game.gameSession?.animationEvents?.handle(event, from: actor, reachesEffectGraphs: false)
    }

    private func effectSubGraphs() -> [AttachedSubGraph] {
        game.effects.visualEffects.instances.compactMap { instance in
            guard let model = instance.spec.artModel else { return nil }
            let anchor: SubGraphAnchor = switch instance.anchor {
            case let .actor(actor): .actor(actor)
            case let .point(position), let .surface(position, _): .point(position)
            }
            return AttachedSubGraph(
                id: .effect(instance.id), anchor: anchor, name: instance.spec.name,
                modelPath: model
            )
        }
    }

    private func armorAddonSubGraphs() -> [AttachedSubGraph] {
        var worn: [(ReferenceKey, [WornArmorAddon])] = game.actorWorld.combatActors()
            .compactMap { actor in
                game.actorPlayback(for: actor.key).map { (actor.key, $0.armorAddons) }
            }
        if let player = game.gameSession?.playerBody?.assembly.visual.wornArmorAddons {
            worn.append((.player, player))
        }
        return worn.flatMap { actor, addons in
            addons.map { addon in
                AttachedSubGraph(
                    id: .armorAddon(actor, armature: addon.armature.rawValue),
                    anchor: .actor(actor), name: addon.modelPath, modelPath: addon.modelPath
                )
            }
        }
    }
}

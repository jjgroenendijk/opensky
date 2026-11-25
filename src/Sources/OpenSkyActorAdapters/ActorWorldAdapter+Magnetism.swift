// What melee magnetism turns with: the object under the crosshair, out to the rule's
// 750 units. docs/engine/combat-assist.md#in-opensky.

public import OpenSkyCombatInterface
public import OpenSkyFormatsESM
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkySessionInterface
public import OpenSkyWorldInterface
import simd

/// What the crosshair pick of melee magnetism reads.
public struct MagnetismSightingInput {
    public var actors: [CombatActorObservation] = []
    public var ownMount: ReferenceKey?
    /// The crosshair's activation target, which reaches less far than the rule.
    public var crosshair: InteractionTarget?
    /// How far along the ray the first solid object is, or nil with none.
    public var wallDistance: (InteractionRay) -> Float? = { _ in nil }

    public init() {}
}

extension ActorWorldAdapter {
    /// The nearest actor the view ray passes through, else the crosshair's activation
    /// target. Nil for a dead actor, for the player's own mount, and behind a wall.
    public static func magnetismSighting(
        along ray: InteractionRay, _ input: MagnetismSightingInput
    ) -> MeleeMagnetism.Sighting? {
        MagnetismReads.magnetismSighting(along: ray, input)
    }

    public func magnetismSighting(along ray: InteractionRay) -> MeleeMagnetism.Sighting? {
        SightingReads(owner: self).magnetismSighting(along: ray)
    }
}

extension ActorWorldAdapter {
    /// Finds the actor the player's attack is drawn to.
    enum MagnetismReads {
        static func magnetismSighting(
            along ray: InteractionRay, _ input: MagnetismSightingInput
        ) -> MeleeMagnetism.Sighting? {
            let actors = input.actors.filter { $0.key != .player }
            let bodies = actors.map { MeleeTarget(key: $0.key, feet: $0.feet, capsule: $0.capsule) }
            if
                let hit = MeleeMagnetismPick.nearestActor(along: ray, actors: bodies),
                let actor = actors.first(where: { $0.key == hit.key })
            {
                guard
                    !actor.isDead, actor.key != input.ownMount,
                    hit.distance < input.wallDistance(ray) ?? .greatestFiniteMagnitude
                else { return nil }
                return MeleeMagnetism.Sighting(actor: actor.key, position: actor.feet)
            }
            guard let target = input.crosshair, target.interaction.action != .talk else {
                return nil
            }
            return MeleeMagnetism.Sighting(actor: nil, position: target.hitPosition)
        }
    }
}

extension ActorWorldAdapter {
    /// Finds the actor a melee swing turns toward.
    struct SightingReads {
        let owner: ActorWorldAdapter

        func magnetismSighting(along ray: InteractionRay) -> MeleeMagnetism.Sighting? {
            let game = owner.game
            var input = MagnetismSightingInput()
            input.actors = owner.combatActors()
            input.ownMount = game.mounts.lastMount
            input.crosshair = game.streamer.interactionTarget
            input.wallDistance = { [streamer = game.streamer] in
                streamer.nearestCollisionHit(ray: $0)?.distance
            }
            return ActorWorldAdapter.magnetismSighting(along: ray, input)
        }
    }
}

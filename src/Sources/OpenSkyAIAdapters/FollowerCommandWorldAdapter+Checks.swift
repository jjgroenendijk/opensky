// The ground a follower is sent to, and whether its morality allows the command.

import OpenSkyActorsInterface
import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyCrimeInterface
import OpenSkyDialogueInterface
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyPlayer
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyScriptingInterface
import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

extension FollowerCommandWorldAdapter {
    var checks: Checks {
        Checks(owner: self, game: game)
    }

    public func followerMorality(_ follower: ReferenceKey) -> Float {
        checks.followerMorality(follower)
    }

    struct Checks {
        let owner: FollowerCommandWorldAdapter
        let game: any FollowerCommandWorldHost

        /// The first ground the view ray meets within the pick distance: collision or terrain.
        func groundTarget() -> FollowerCommandTarget? {
            guard
                let camera = game.gameSession?.freeFlyCamera,
                let ray = InteractionRay(
                    origin: camera.position, direction: camera.forward,
                    maximumDistance: owner.pickReach
                )
            else { return nil }
            let hit = game.streamer.nearestCollisionHit(ray: ray)
            let reach = hit?.distance ?? ray.maximumDistance
            let terrain = stride(
                from: FollowerCommandWorldAdapter.terrainStep,
                through: reach,
                by: FollowerCommandWorldAdapter.terrainStep
            )
            .lazy.map { ray.origin + ray.direction * $0 }
            .first { point in
                game.streamer.sampleTerrain(at: SIMD2(point.x, point.y))
                    .map { point.z <= $0.height } ?? false
            }
            guard let point = terrain ?? hit?.position else { return nil }
            return FollowerCommandTarget(key: nil, kind: .ground, position: point)
        }

        func followerMorality(_ follower: ReferenceKey) -> Float {
            guard
                let index = ActorValueIdentity.index(named: "Morality"),
                let holder = game.actorWorld.actorValueHolder(for: follower)
            else { return FollowerCommandRules.lawfulMorality }
            return game.actorValues.runtime?.value(at: index, on: holder)
                ?? FollowerCommandRules.lawfulMorality
        }
    }
}

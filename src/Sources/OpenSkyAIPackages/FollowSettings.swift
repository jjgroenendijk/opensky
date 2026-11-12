// How followers share the space behind their leader: `fFollowSpaceBetweenFollowers` and
// `fFollowRunMinSlowdownMultiplier`. The CK wiki table names both without a use, so each
// use is OpenSky's reading (docs/engine/package-schedules.md#followers).

public import OpenSkyFormatsESM
import OpenSkyGameData
public import OpenSkyWorldInterface
import simd

extension PackageCoordinator {
    /// Where the other actors that follow `leader` stand.
    func fellowFollowers(of leader: ReferenceKey, excluding actor: ReferenceKey) -> [SIMD3<Float>] {
        executions.keys.sorted().compactMap { other in
            guard
                other != actor,
                executions[other]?.follows(leader) == true
            else { return nil }
            return world?.packageActorPosition(other)
        }
    }

    /// The running slowdown floor for a follower's walk, or nil for an actor with no pace.
    public func followRunSlowdown(for actor: ReferenceKey) -> FollowSettings? {
        movement.paces[actor] == nil ? nil : settings.follow
    }
}

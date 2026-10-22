// How followers share the space behind their leader: `fFollowSpaceBetweenFollowers` and
// `fFollowRunMinSlowdownMultiplier`. The CK wiki table names both without a use, so each
// use is OpenSky's reading (docs/engine/package-schedules.md#followers).

import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldInterface
import simd

nonisolated public struct FollowSettings: Equatable, Sendable {
    /// The room, in units, one follower keeps from another of the same leader.
    public var spaceBetweenFollowers: Float = 192
    /// A running follower slows as it nears its goal, to no less than this share of its
    /// running speed.
    public var runMinSlowdownMultiplier: Float = 0.75

    public static let vanilla = Self()

    public init() {}

    public static func resolve(store: GameSettingStore) -> Self {
        var settings = vanilla
        store.read("fFollowSpaceBetweenFollowers", into: &settings, \.spaceBetweenFollowers)
        store.read(
            "fFollowRunMinSlowdownMultiplier", into: &settings, \.runMinSlowdownMultiplier
        )
        return settings
    }

    /// `goal` pushed away from each fellow follower closer than `spacing`, in fellow order.
    public static func spacedGoal(
        _ goal: SIMD3<Float>, fellows: [SIMD3<Float>], spacing: Float
    ) -> SIMD3<Float> {
        guard spacing.isFinite, spacing > 0 else { return goal }
        var spaced = goal
        for fellow in fellows {
            let offset = SIMD2(spaced.x - fellow.x, spaced.y - fellow.y)
            let distance = simd_length(offset)
            guard distance < spacing else { continue }
            let direction = distance > 1e-3 ? offset / distance : SIMD2<Float>(1, 0)
            let moved = SIMD2(fellow.x, fellow.y) + direction * spacing
            spaced = SIMD3(moved.x, moved.y, spaced.z)
        }
        return spaced
    }

    /// The share of running speed a running follower keeps `remaining` units from its
    /// goal: it falls with the distance inside `slowingDistance`, but not below the floor.
    public func runSpeedScale(remaining: Float, slowingDistance: Float) -> Float {
        let floor = runMinSlowdownMultiplier.isFinite
            ? min(max(runMinSlowdownMultiplier, 0), 1) : 1
        guard slowingDistance > 0, remaining.isFinite else { return 1 }
        return max(floor, min(1, remaining / slowingDistance))
    }
}

extension PackageCoordinator {
    /// Where the other actors that follow `leader` stand.
    func fellowFollowers(of leader: ReferenceKey, excluding actor: ReferenceKey) -> [SIMD3<Float>] {
        executions.keys.sorted().compactMap { other in
            guard
                other != actor,
                executions[other]?.runner.running.values.contains(where: {
                    ($0.machine.kind == .follow || $0.machine.kind == .followTo)
                        && $0.machine.setup.watched == leader
                }) == true
            else { return nil }
            return world?.packageActorPosition(other)
        }
    }

    /// The running slowdown floor for a follower's walk, or nil for an actor with no pace.
    public func followRunSlowdown(for actor: ReferenceKey) -> FollowSettings? {
        paces[actor] == nil ? nil : followSettings
    }
}

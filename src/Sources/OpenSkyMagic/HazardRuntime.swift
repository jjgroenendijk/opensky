// Lingering hazards: a `HAZD` placed in a cell or spawned at runtime, hitting every
// actor in its radius once per target interval. Pure: placements and actor capsules
// in, hits out. See docs/engine/traps.md and docs/formats/hazards.md.

import Foundation
public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyMagicInterface
public import OpenSkyPhysics

/// One hazard hitting the actors in its radius this step.
nonisolated public struct HazardHit: Equatable, Sendable {
    public let hazard: ReferenceKey
    public let spec: HazardSpec
    public let targets: [SpellHitTarget]
}

nonisolated public struct HazardRuntime: Equatable, Sendable {
    public private(set) var active: [ReferenceKey: ActiveHazard] = [:]
    private var spawnOrder: [ReferenceKey] = []

    public init() {}

    /// Adds or replaces a hazard. A spawn past its record's limit drops the oldest copy.
    public mutating func place(
        _ spec: HazardSpec, id: ReferenceKey, at position: SIMD3<Float>, source: HazardSource
    ) {
        if source == .spawned {
            let copies = spawnOrder.filter { active[$0]?.spec.hazard == spec.hazard }
            if spec.limit > 0, copies.count >= Int(spec.limit), let oldest = copies.first {
                remove(oldest)
            }
            spawnOrder.removeAll { $0 == id }
            spawnOrder.append(id)
        }
        active[id] = ActiveHazard(id: id, spec: spec, position: position, source: source)
    }

    public mutating func remove(_ id: ReferenceKey) {
        active[id] = nil
        spawnOrder.removeAll { $0 == id }
    }

    /// Drops every hazard a cell placed, as it leaves the live world.
    public mutating func removeAll(placedIn cell: CellSceneLocation) {
        for (id, hazard) in active where hazard.source == .placed(cell) {
            remove(id)
        }
    }

    /// Ages every hazard by `seconds` and returns who each one hits, in id order.
    /// An actor is hit on entering the radius and then once per target interval.
    public mutating func step(
        _ seconds: Float,
        candidates: [MeleeTarget],
        player: ReferenceKey = .player
    ) -> [HazardHit] {
        guard seconds > 0, seconds.isFinite else { return [] }
        var hits: [HazardHit] = []
        for id in active.keys.sorted() {
            guard var hazard = active[id] else { continue }
            hazard.age += seconds
            if let remaining = hazard.remainingLifetime, remaining <= 0 {
                remove(id)
                continue
            }
            let targets = Self.targets(
                of: &hazard,
                seconds: seconds,
                candidates: candidates,
                player: player
            )
            if !targets.isEmpty {
                hazard.tickCount += 1
                hits.append(HazardHit(hazard: id, spec: hazard.spec, targets: targets))
            }
            active[id] = hazard
        }
        return hits
    }

    private static func targets(
        of hazard: inout ActiveHazard,
        seconds: Float,
        candidates: [MeleeTarget],
        player: ReferenceKey
    ) -> [SpellHitTarget] {
        let inside = candidates
            .filter { !hazard.spec.affectsPlayerOnly || $0.key == player }
            .map {
                (key: $0.key, distance: SpellHitTargeting.distance(from: hazard.position, to: $0))
            }
            .filter { $0.distance <= hazard.spec.radius }
            .sorted { ($0.distance, $0.key) < ($1.distance, $1.key) }
        var cooldowns: [ReferenceKey: Float] = [:]
        var targets: [SpellHitTarget] = []
        for actor in inside {
            let remaining = (hazard.cooldowns[actor.key] ?? 0) - seconds
            if remaining <= 0 {
                targets.append(SpellHitTarget(key: actor.key, distance: actor.distance))
                cooldowns[actor.key] = hazard.spec.targetInterval
            } else {
                cooldowns[actor.key] = remaining
            }
        }
        hazard.cooldowns = cooldowns
        return targets
    }
}

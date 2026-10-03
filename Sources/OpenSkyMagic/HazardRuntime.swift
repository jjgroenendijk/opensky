// Lingering hazards: a `HAZD` placed in a cell or spawned at runtime, hitting every
// actor in its radius once per target interval. Pure: placements and actor capsules
// in, hits out. See docs/engine/traps.md and docs/formats/hazards.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface
import OpenSkyPhysics

/// The `HAZD` numbers a hazard runs on, with its spell already resolved.
nonisolated public struct HazardSpec: Equatable, Sendable {
    /// A target interval at or below zero hits this often, so a bad record cannot
    /// hit every frame. OpenSky's value.
    public static let minimumInterval: Float = 0.1

    public let hazard: ReferenceKey
    public let name: String
    /// The `SPEL` it applies, or nil when the record names none.
    public let spell: ReferenceKey?
    public let radius: Float
    /// Seconds a spawned hazard lasts. At or below zero it lasts until removed.
    public let lifetime: Float
    public let targetInterval: Float
    /// How many spawned copies may exist at once. Zero means no limit.
    public let limit: UInt32
    public let affectsPlayerOnly: Bool

    public init(
        hazard: ReferenceKey,
        name: String,
        spell: ReferenceKey?,
        radius: Float,
        lifetime: Float,
        targetInterval: Float,
        limit: UInt32 = 0,
        affectsPlayerOnly: Bool = false
    ) {
        self.hazard = hazard
        self.name = name
        self.spell = spell
        self.radius = radius.isFinite ? max(0, radius) : 0
        self.lifetime = lifetime.isFinite ? lifetime : 0
        self.targetInterval = targetInterval.isFinite
            ? max(targetInterval, Self.minimumInterval) : Self.minimumInterval
        self.limit = limit
        self.affectsPlayerOnly = affectsPlayerOnly
    }
}

/// Where a hazard came from: a `PHZD` of a resident cell, or a runtime spawn.
nonisolated public enum HazardSource: Hashable, Sendable {
    case placed(CellSceneLocation)
    case spawned
}

/// One hazard in the world.
nonisolated public struct ActiveHazard: Equatable, Sendable {
    public let id: ReferenceKey
    public let spec: HazardSpec
    public let position: SIMD3<Float>
    public let source: HazardSource
    public internal(set) var age: Float = 0
    /// Seconds until each actor in the radius may be hit again.
    public internal(set) var cooldowns: [ReferenceKey: Float] = [:]
    /// Steps on which this hazard hit at least one actor.
    public internal(set) var tickCount = 0

    /// Only a spawned hazard expires: a placed one lives while its cell is resident
    /// and its enable state allows. OpenSky's reading of the lifetime field.
    public var remainingLifetime: Float? {
        guard source == .spawned, spec.lifetime > 0 else { return nil }
        return max(0, spec.lifetime - age)
    }
}

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

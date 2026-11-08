import Foundation
public import OpenSkyFormatsESM
public import OpenSkyGameData
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

/// One hazard in the world.
nonisolated public struct ActiveHazard: Equatable, Sendable {
    public let id: ReferenceKey
    public let spec: HazardSpec
    public let position: SIMD3<Float>
    public let source: HazardSource
    public package(set) var age: Float = 0
    /// Seconds until each actor in the radius may be hit again.
    public package(set) var cooldowns: [ReferenceKey: Float] = [:]
    /// Steps on which this hazard hit at least one actor.
    public package(set) var tickCount = 0

    /// Only a spawned hazard expires: a placed one lives while its cell is resident
    /// and its enable state allows. OpenSky's reading of the lifetime field.
    public var remainingLifetime: Float? {
        guard source == .spawned, spec.lifetime > 0 else { return nil }
        return max(0, spec.lifetime - age)
    }

    public init(
        id: ReferenceKey,
        spec: HazardSpec,
        position: SIMD3<Float>,
        source: HazardSource
    ) {
        self.id = id
        self.spec = spec
        self.position = position
        self.source = source
    }
}

/// Where a hazard came from: a `PHZD` of a resident cell, or a runtime spawn.
nonisolated public enum HazardSource: Hashable, Sendable {
    case placed(CellSceneLocation)
    case spawned
}

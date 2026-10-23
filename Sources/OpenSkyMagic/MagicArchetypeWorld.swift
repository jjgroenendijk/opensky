// The part of the world the later archetypes reach: commanding, race changes, holding
// bodies and actors, and the Guide path. Every member has a default that does
// nothing, so a session without the seam leaves the effect counted and harmless.
// See docs/engine/magic-archetypes.md.

import OpenSkyFormatsESM
import simd

/// Where an actor looks from and toward.
nonisolated public struct MagicAimRay: Equatable, Sendable {
    public let origin: SIMD3<Float>
    public let direction: SIMD3<Float>

    public init(origin: SIMD3<Float>, direction: SIMD3<Float>) {
        self.origin = origin
        self.direction = direction
    }
}

/// A loose rigid body as Telekinesis steers it.
nonisolated public struct MagicHeldBody: Equatable, Sendable {
    public let position: SIMD3<Float>
    public let velocity: SIMD3<Float>
    public let mass: Float

    public init(position: SIMD3<Float>, velocity: SIMD3<Float>, mass: Float) {
        self.position = position
        self.velocity = velocity
        self.mass = mass
    }
}

/// What a Guide trail follows, or why it has none.
nonisolated public enum MagicGuidePath: Equatable, Sendable {
    /// The caster has no quest target.
    case noMarker
    /// A target exists, but no path reaches it.
    case noPath
    /// World points from the caster toward the target, the caster first.
    case path([SIMD3<Float>])
}

@MainActor
public protocol MagicArchetypeWorld: AnyObject {
    /// `actor` takes `caster`'s side, as a summon does.
    func commandActor(_ actor: ReferenceKey, for caster: ReferenceKey)
    /// Living actors within `radius` world units of `key`, other than it.
    func livingActors(near key: ReferenceKey, radius: Float) -> [ReferenceKey]
    /// Changes `key`'s race to `race`, a load-order `RACE`. False when it cannot.
    func changeRace(of key: ReferenceKey, to race: FormID) -> Bool
    /// Sets the eaten flag `HasBeenEaten` reads.
    func markEaten(_ key: ReferenceKey)
    /// Where `key` looks from and toward.
    func aimRay(of key: ReferenceKey) -> MagicAimRay?
    /// The loose rigid body `caster`'s aim reaches within `reach`, if any.
    func telekinesisTarget(for caster: ReferenceKey, within reach: Float) -> ReferenceKey?
    func heldBody(_ key: ReferenceKey) -> MagicHeldBody?
    func pushBody(_ key: ReferenceKey, impulse: SIMD3<Float>)
    /// Holds `actor` at `point`, or lets it go when `point` is nil.
    func holdActor(_ actor: ReferenceKey, at point: SIMD3<Float>?)
    /// Sends `actor` away along `direction`, as a throw.
    func throwActor(_ actor: ReferenceKey, along direction: SIMD3<Float>, force: Float)
    func guidePath(for caster: ReferenceKey) -> MagicGuidePath
    /// Places the `HAZD` `hazard` at `point`. False when it cannot.
    @discardableResult
    func placeHazard(_ hazard: ReferenceKey, at point: SIMD3<Float>) -> Bool
}

extension MagicArchetypeWorld {
    public func commandActor(_: ReferenceKey, for _: ReferenceKey) {}

    public func livingActors(near _: ReferenceKey, radius _: Float) -> [ReferenceKey] {
        []
    }

    public func changeRace(of _: ReferenceKey, to _: FormID) -> Bool {
        false
    }

    public func markEaten(_: ReferenceKey) {}

    public func aimRay(of _: ReferenceKey) -> MagicAimRay? {
        nil
    }

    public func telekinesisTarget(for _: ReferenceKey, within _: Float) -> ReferenceKey? {
        nil
    }

    public func heldBody(_: ReferenceKey) -> MagicHeldBody? {
        nil
    }

    public func pushBody(_: ReferenceKey, impulse _: SIMD3<Float>) {}

    public func holdActor(_: ReferenceKey, at _: SIMD3<Float>?) {}

    public func throwActor(_: ReferenceKey, along _: SIMD3<Float>, force _: Float) {}

    public func guidePath(for _: ReferenceKey) -> MagicGuidePath {
        .noMarker
    }

    @discardableResult
    public func placeHazard(_: ReferenceKey, at _: SIMD3<Float>) -> Bool {
        false
    }
}

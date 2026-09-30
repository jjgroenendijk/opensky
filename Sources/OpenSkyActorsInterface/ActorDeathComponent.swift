// Persistent death: the component that keeps an actor dead after a reload. It is
// a one-way latch, separate from the regenerating actor values. Only the resting
// root transform is stored, not the bone pose, so a corpse reloads in its rest
// pose. See docs/engine/ragdoll.md and docs/engine/runtime-state.md.

import OpenSkyFormatsCore
import OpenSkyWorldState
import simd

/// One actor's death, and where its corpse ended up.
nonisolated public struct ActorDeathState: WorldStateComponent, Equatable, Sendable {
    /// Set once the actor's health reached zero and the death events were
    /// raised. Never cleared by damage or regeneration.
    public var isDead: Bool
    /// Where the ragdoll came to rest, in world space, or nil while it is still
    /// falling. A corpse that is still moving when its cell unloads keeps the
    /// last resting transform it recorded, exactly as a dynamic body does.
    public var restingTransform: ReferenceTransformOverride?
    /// Whether the corpse has been searched at least once, so a looted body can
    /// be told from an untouched one without reading its inventory.
    public var wasLooted: Bool

    /// The value an actor takes the moment it dies, before anything has settled.
    public static let justDied = ActorDeathState(isDead: true)

    public static var componentKind: WorldStateComponentKind {
        .death
    }

    public init(
        isDead: Bool,
        restingTransform: ReferenceTransformOverride? = nil,
        wasLooted: Bool = false
    ) {
        self.isDead = isDead
        self.restingTransform = restingTransform
        self.wasLooted = wasLooted
    }

    /// This state with the ragdoll's settled root pose recorded.
    public func settled(at position: SIMD3<Float>, orientation: simd_quatf) -> Self {
        ActorDeathState(
            isDead: isDead,
            restingTransform: ReferenceTransformOverride(
                position: position,
                rotation: MatrixMath.eulerAngles(of: orientation)
            ),
            wasLooted: wasLooted
        )
    }

    /// This state marked as searched.
    public var looted: Self {
        ActorDeathState(
            isDead: isDead, restingTransform: restingTransform, wasLooted: true
        )
    }
}

nonisolated extension WorldStateComponentKind {
    /// One actor's death and the resting transform its ragdoll settled at. A slot
    /// of its own rather than a field on `actorValues` because the two have
    /// different lifetimes: a current-health float is rewritten every regeneration
    /// step, while death is a latch nothing but a resurrection clears.
    public static let death = Self(rawValue: "death", order: 9)
}

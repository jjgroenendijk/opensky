// Persistent death (issue #197, roadmap item 15.6): the world-state component
// that makes an actor still dead after a save and a reload.
//
// It sits beside `ActorValueState` rather than inside it, following the same
// rule the quest slots follow. The two have different lifetimes: actor values
// are a live simulation quantity that regeneration rewrites every fixed step,
// while death is a one-way latch that nothing but a resurrection clears. Folding
// the latch into the regenerating value would mean rewriting the death record
// sixty times a second for no change, and would make "is this actor dead" a
// question about a float rather than about a fact.
//
// ## What is persisted, and what is not
//
// The resting **root** transform, not the per-bone pose. A vanilla ragdoll is
// eighteen bodies; the pose that settles them is a hundred and forty-four floats
// per corpse, and every one of them would have to survive a save, a load, and a
// cell rebuild to be worth recording.
//
// The visual consequence is stated plainly because it is real and a player can
// see it: **a corpse reloads lying at the place and facing it came to rest, in
// the skeleton's rest pose rather than in the exact tangle it died in.** A body
// that fell face-down across a stair comes back face-down at the foot of the
// stair, laid out straight. Recording the full pose is a later item's to take
// on if it is ever worth the save-file cost; nothing here forecloses it, because
// the component would gain a field rather than change shape.
//
// Documented in docs/engine/ragdoll.md and docs/engine/runtime-state.md.

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

nonisolated extension WorldStateComponentValue {
    public static func death(_ value: ActorDeathState) -> Self {
        Self(value)
    }
}

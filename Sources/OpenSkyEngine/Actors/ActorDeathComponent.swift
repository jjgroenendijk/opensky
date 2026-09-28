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

import simd

/// One actor's death, and where its corpse ended up.
nonisolated struct ActorDeathState: WorldStateComponent, Equatable {
    /// Set once the actor's health reached zero and the death events were
    /// raised. Never cleared by damage or regeneration.
    var isDead: Bool
    /// Where the ragdoll came to rest, in world space, or nil while it is still
    /// falling. A corpse that is still moving when its cell unloads keeps the
    /// last resting transform it recorded, exactly as a dynamic body does.
    var restingTransform: ReferenceTransformOverride?
    /// Whether the corpse has been searched at least once, so a looted body can
    /// be told from an untouched one without reading its inventory.
    var wasLooted: Bool

    /// The value an actor takes the moment it dies, before anything has settled.
    static let justDied = ActorDeathState(isDead: true)

    static var componentKind: WorldStateComponentKind {
        .death
    }

    var erased: WorldStateComponentValue {
        .death(self)
    }

    init(
        isDead: Bool,
        restingTransform: ReferenceTransformOverride? = nil,
        wasLooted: Bool = false
    ) {
        self.isDead = isDead
        self.restingTransform = restingTransform
        self.wasLooted = wasLooted
    }

    init?(erased: WorldStateComponentValue) {
        guard case let .death(value) = erased else { return nil }
        self = value
    }

    /// This state with the ragdoll's settled root pose recorded.
    func settled(at position: SIMD3<Float>, orientation: simd_quatf) -> Self {
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
    var looted: Self {
        ActorDeathState(
            isDead: isDead, restingTransform: restingTransform, wasLooted: true
        )
    }
}

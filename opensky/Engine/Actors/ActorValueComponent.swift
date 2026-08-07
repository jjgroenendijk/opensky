// Actor values as a world-state component (issue #194, roadmap item 15.3): the
// value type holding one actor's current health, magicka and stamina once
// anything has touched them.
//
// The component lives here rather than in `WorldStateComponents.swift` for the
// same reason `ReferenceInventoryState` and `QuestRuntimeState` live beside
// their own subsystems: it carries behaviour of its own — clamping, the
// zero-health rule — rather than being a plain field bag. Only the
// `WorldStateComponentKind` case and the `WorldStateComponentValue` case sit
// with the rest, so every store operation stays generic over the protocol.
//
// Current values only. The maximums are *not* stored, and that is the whole
// design: they are a pure function of the RACE, CLAS and NPC_ records
// (`ActorValueResolver`), so storing them would let a save keep numbers a
// changed load order no longer authors. It is the same rule the inventory
// baseline and the quest baseline already follow — re-derive, never persist.
//
// One invariant holds for every value of this type, enforced in `init` rather
// than checked at use sites: every value is finite and not negative. That is
// what lets the runtime, the HUD and the save each assume it separately.
//
// Documented in docs/engine/actor-values.md.

import Foundation

/// One actor's current primary values.
nonisolated struct ActorValueState: WorldStateComponent {
    /// Current health, magicka and stamina. Never negative, never NaN, and
    /// never above the maximums the runtime clamped it against — though this
    /// type cannot enforce that last one on its own, because it does not know
    /// the maximums.
    private(set) var current: ActorValues

    static var componentKind: WorldStateComponentKind {
        .actorValues
    }

    var erased: WorldStateComponentValue {
        .actorValues(self)
    }

    /// The flag item 15.6 consumes to start death and ragdoll handling.
    ///
    /// Derived rather than stored: a stored flag and a stored health can
    /// disagree, and after a save round trip there would be no way to say which
    /// of the two was right. Zero exactly, not a small epsilon — every path
    /// that lowers health clamps at zero, so an actor at zero health arrived
    /// there by the clamp.
    var hasZeroHealth: Bool {
        current.health <= 0
    }

    /// Normalizes on the way in, which is also what makes this the save
    /// decoder's entry point: a corrupt file degrades into a valid state rather
    /// than failing the whole load.
    init(current: ActorValues) {
        var normalized = ActorValues.zero
        for kind in ActorValueKind.allCases {
            let value = current[kind]
            normalized[kind] = value.isFinite ? max(0, value) : 0
        }
        self.current = normalized
    }

    init?(erased: WorldStateComponentValue) {
        guard case let .actorValues(value) = erased else { return nil }
        self = value
    }

    /// The state an actor has before anything touches it: every value at its
    /// maximum.
    ///
    /// Actors enter the world full. Nothing in a plugin authors a "starts at
    /// half health" actor — the Creation Kit's Stats tab has no such field —
    /// so a partially depleted actor is always something the session did, and
    /// therefore always a component rather than a baseline.
    static func baseline(maximums: ActorValues) -> ActorValueState {
        ActorValueState(current: maximums)
    }

    /// This state with `amount` taken off one value, floored at zero.
    ///
    /// A non-positive or non-finite `amount` changes nothing rather than
    /// healing: "damage" that restores is a caller bug, and letting it through
    /// would make a negative weapon damage into a heal.
    func damaging(_ kind: ActorValueKind, by amount: Float) -> Self {
        guard amount.isFinite, amount > 0 else { return self }
        var updated = current
        updated[kind] = max(0, updated[kind] - amount)
        return ActorValueState(current: updated)
    }

    /// This state with `amount` added to one value, capped at `maximum`.
    ///
    /// A non-positive or non-finite `amount` changes nothing, mirroring
    /// `damaging`.
    func restoring(_ kind: ActorValueKind, by amount: Float, maximum: Float) -> Self {
        guard amount.isFinite, amount > 0 else { return self }
        var updated = current
        let limit = maximum.isFinite ? max(0, maximum) : 0
        updated[kind] = min(limit, updated[kind] + amount)
        return ActorValueState(current: updated)
    }

    /// This state pulled inside `maximums`, which is what a caller applies
    /// after the records behind an actor changed and its maximums shrank.
    func clamped(to maximums: ActorValues) -> Self {
        ActorValueState(current: current.clamped(to: maximums))
    }
}

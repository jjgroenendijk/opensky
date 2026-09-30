// Actor values as a world-state component: one actor's current values once
// anything touched them. Maximums are not stored; they are re-derived from RACE,
// CLAS, and NPC_ records, so a changed load order applies. Base writes are
// offsets for the same reason. Every value is finite and not negative, enforced
// in `init`. See docs/engine/actor-value-store.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldState

/// One actor's current primary values, plus whatever it has stored for the
/// rest of the actor-value table.
nonisolated public struct ActorValueState: WorldStateComponent, Sendable {
    /// Current health, magicka and stamina. Never negative, never NaN, and
    /// never above the maximums the runtime clamped it against — though this
    /// type cannot enforce that last one on its own, because it does not know
    /// the maximums.
    public private(set) var current: ActorValues

    /// Every actor value this actor moved off its derived baseline, by vanilla table
    /// index. Sparse on purpose: an absent index reads its baseline, and an override
    /// that returns to nothing is dropped. Deltas only, so a primary's `current` and
    /// its override never disagree.
    public private(set) var overrides: [Int32: ActorValueOverride]

    public static var componentKind: WorldStateComponentKind {
        .actorValues
    }

    /// Whether the actor is dead. Derived, not stored, so it cannot disagree with
    /// health. Exactly zero: every path that lowers health clamps at zero.
    public var hasZeroHealth: Bool {
        current.health <= 0
    }

    /// Normalizes on the way in, so a corrupt save degrades to a valid state. An
    /// override outside the vanilla table, or one that changes nothing, is dropped.
    public init(current: ActorValues, overrides: [Int32: ActorValueOverride] = [:]) {
        var normalized = ActorValues.zero
        for kind in ActorValueKind.allCases {
            let value = current[kind]
            normalized[kind] = value.isFinite ? max(0, value) : 0
        }
        self.current = normalized
        self.overrides = overrides.filter { index, override in
            ActorValueIdentity.isVanilla(index: index) && !override.isEmpty
        }
    }

    /// The state an actor has before anything touches it: every value at its
    /// maximum. No plugin authors a partly depleted actor.
    public static func baseline(maximums: ActorValues) -> ActorValueState {
        ActorValueState(current: maximums)
    }

    /// This state with `amount` taken off one value, floored at zero.
    ///
    /// A non-positive or non-finite `amount` changes nothing rather than
    /// healing: "damage" that restores is a caller bug, and letting it through
    /// would make a negative weapon damage into a heal.
    public func damaging(_ kind: ActorValueKind, by amount: Float) -> Self {
        guard amount.isFinite, amount > 0 else { return self }
        var updated = current
        updated[kind] = max(0, updated[kind] - amount)
        return ActorValueState(current: updated, overrides: overrides)
    }

    /// This state with `amount` added to one value, capped at `maximum`.
    ///
    /// A non-positive or non-finite `amount` changes nothing, mirroring
    /// `damaging`.
    public func restoring(_ kind: ActorValueKind, by amount: Float, maximum: Float) -> Self {
        guard amount.isFinite, amount > 0 else { return self }
        var updated = current
        let limit = maximum.isFinite ? max(0, maximum) : 0
        updated[kind] = min(limit, updated[kind] + amount)
        return ActorValueState(current: updated, overrides: overrides)
    }

    /// This state pulled inside `maximums`, which is what a caller applies
    /// after the records behind an actor changed and its maximums shrank.
    ///
    /// The override table is untouched: an override is a delta on a derived
    /// baseline, and a shrinking maximum does not make the session's own
    /// contribution to it any smaller.
    public func clamped(to maximums: ActorValues) -> Self {
        ActorValueState(current: current.clamped(to: maximums), overrides: overrides)
    }

    // MARK: - The override table

    /// `index`'s value as a caller reads it: the stored override laid over
    /// `baseline`, or the unmodified entry `baseline` describes on its own.
    ///
    /// Answers for every vanilla index, primaries included. Only an index
    /// outside the table is nil, because only that names no actor value.
    public func entry(at index: Int32, baseline: Float) -> ActorValueEntry? {
        guard ActorValueIdentity.isVanilla(index: index) else { return nil }
        return (overrides[index] ?? .none).resolved(baseline: baseline)
    }

    /// This state with `index`'s entry stored as a deviation from `baseline`,
    /// or dropped when the new entry says exactly what `baseline` already says.
    ///
    /// Dropping rather than storing a baseline-equal entry is what keeps the
    /// save and the dirty counts honest: an actor whose fire resistance was
    /// raised and then lowered again is an actor nothing happened to.
    public func setting(
        _ entry: ActorValueEntry,
        at index: Int32,
        baseline: Float
    ) -> Self {
        setting(ActorValueOverride.storing(entry, baseline: baseline), at: index)
    }

    /// This state with `index`'s override replaced outright, or dropped when it
    /// says nothing.
    public func setting(_ override: ActorValueOverride, at index: Int32) -> Self {
        guard ActorValueIdentity.isVanilla(index: index) else { return self }
        var updated = overrides
        if override.isEmpty {
            updated.removeValue(forKey: index)
        } else {
            updated[index] = override
        }
        return ActorValueState(current: current, overrides: updated)
    }

    /// `index`'s stored override, which is `.none` for a value nothing has
    /// touched.
    public func override(at index: Int32) -> ActorValueOverride {
        overrides[index] ?? .none
    }
}

nonisolated extension WorldStateComponentKind {
    /// One actor's current health, magicka and stamina. Current values only: the
    /// maximums re-derive from the RACE, CLAS and NPC_ records through
    /// `ActorValueResolver`, exactly as an inventory baseline re-derives from its
    /// CNTO list.
    public static let actorValues = Self(rawValue: "actorValues", order: 8)
}

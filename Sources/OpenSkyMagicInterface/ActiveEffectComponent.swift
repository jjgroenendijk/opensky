// Active effects as a world-state component: every magic effect on one actor.
// It owns sequence assignment, stacking, and expiry. Its own slot, because
// effects change on events while health changes every step.
// See docs/engine/magic.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyWorldState

/// Every magic effect currently acting on one actor.
nonisolated public struct ActiveEffectState: WorldStateComponent, Sendable {
    /// The effects, in ascending `sequence` order — the order they were
    /// applied, which is also the order the save writes and a readout lists.
    public private(set) var effects: [ActiveEffect]

    public static var componentKind: WorldStateComponentKind {
        .activeEffects
    }

    /// Normalizes on the way in, so a corrupt save degrades to a valid state. An
    /// effect with no values is dropped, and so is a timed one with duration not
    /// above zero. A constant effect is kept whatever its duration.
    public init(effects: [ActiveEffect] = []) {
        self.effects = effects
            .filter { !$0.values.isEmpty && ($0.duration > 0 || $0.isConstant) }
            .sorted { $0.sequence < $1.sequence }
    }

    public var isEmpty: Bool {
        effects.isEmpty
    }

    /// The sequence number the next application on this actor gets.
    ///
    /// One past the highest in use rather than a count, so dispelling the only
    /// effect and applying another cannot reuse a number a save still refers
    /// to.
    public var nextSequence: UInt64 {
        (effects.map(\.sequence).max() ?? 0) &+ 1
    }

    // MARK: - Queries

    /// Whether any effect on this actor is an application of `effect`, which
    /// the `HasMagicEffect` condition and Papyrus native read.
    public func hasEffect(_ effect: ReferenceKey) -> Bool {
        effects.contains { $0.effect == effect }
    }

    /// The total each actor value's temporary modifier slot should hold for
    /// this actor, keyed by index.
    ///
    /// This is the authority the save relies on: `AVOV` deliberately does not
    /// persist the temporary modifier, so after a load the slot is re-derived
    /// from here rather than read back off disk twice.
    public var ownedModifiers: [Int32: Float] {
        effects.reduce(into: [:]) { totals, effect in
            for value in effect.values where value.applied != 0 {
                totals[value.index, default: 0] += value.applied
            }
        }
    }

    // MARK: - Mutations

    /// This state with `effect` added.
    ///
    /// The caller assigns the sequence through `nextSequence`; adding an effect
    /// whose sequence is already in use replaces the one that had it, which is
    /// what makes a per-tick rewrite of one effect an ordinary update rather
    /// than a duplicate.
    public func adding(_ effect: ActiveEffect) -> ActiveEffectState {
        var updated = effects.filter { $0.sequence != effect.sequence }
        updated.append(effect)
        return ActiveEffectState(effects: updated)
    }

    /// This state with every effect in `replacements` written over the effect
    /// that shares its sequence, and everything else left alone.
    public func replacing(_ replacements: [ActiveEffect]) -> ActiveEffectState {
        guard !replacements.isEmpty else { return self }
        var bySequence: [UInt64: ActiveEffect] = [:]
        for effect in replacements {
            bySequence[effect.sequence] = effect
        }
        return ActiveEffectState(effects: effects.map { bySequence[$0.sequence] ?? $0 })
    }

    /// This state without the effects whose sequences `sequences` names.
    public func removing(sequences: Set<UInt64>) -> ActiveEffectState {
        guard !sequences.isEmpty else { return self }
        return ActiveEffectState(effects: effects.filter { !sequences.contains($0.sequence) })
    }

    /// Every effect whose duration has run out.
    public var expired: [ActiveEffect] {
        effects.filter(\.isExpired)
    }
}

nonisolated extension WorldStateComponentKind {
    /// Every magic effect currently acting on one actor. A slot of its own beside
    /// `actorValues` for the lifetime reason `death` and `combat` are separate
    /// slots: the values beside it are rewritten sixty times a second, while an
    /// effect list changes only when something is applied, expires or is dispelled.
    public static let activeEffects = Self(rawValue: "activeEffects", order: 12)
}

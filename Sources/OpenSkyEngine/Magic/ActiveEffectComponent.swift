// Active effects as a world-state component (issue #469, roadmap item 19.6):
// every magic effect currently acting on one actor.
//
// The component lives here rather than in `WorldStateComponents.swift` for the
// same reason `ReferenceInventoryState` and `ActorValueState` live beside their
// own subsystems: it carries behaviour of its own — sequence assignment, the
// stacking rules, expiry — rather than being a plain field bag. Only the
// `WorldStateComponentKind` case and the `WorldStateComponentValue` case sit
// with the rest, so every store operation stays generic over the protocol.
//
// A slot of its own beside `actorValues` rather than a field on it, for the
// lifetime reason `death` and `combat` are separate slots: a current-health
// float is rewritten sixty times a second, while an effect list changes when
// something is applied, expires or is dispelled.
//
// Documented in docs/engine/magic.md.

import Foundation

/// Every magic effect currently acting on one actor.
nonisolated struct ActiveEffectState: WorldStateComponent {
    /// The effects, in ascending `sequence` order — the order they were
    /// applied, which is also the order the save writes and a readout lists.
    private(set) var effects: [ActiveEffect]

    static var componentKind: WorldStateComponentKind {
        .activeEffects
    }

    var erased: WorldStateComponentValue {
        .activeEffects(self)
    }

    /// Normalizes on the way in, which is also what makes this the save
    /// decoder's entry point: a corrupt file degrades into a valid state rather
    /// than failing the whole load.
    ///
    /// An effect with no values acts on nothing and is dropped, as is a *timed*
    /// one whose duration is not above zero — a zero-duration effect applies
    /// once and is never stored, so one appearing here is corruption rather than
    /// an instantaneous effect that somehow persisted. A constant effect is the
    /// exception and is kept whatever its duration says, because no duration
    /// bounds it (issue #472).
    init(effects: [ActiveEffect] = []) {
        self.effects = effects
            .filter { !$0.values.isEmpty && ($0.duration > 0 || $0.isConstant) }
            .sorted { $0.sequence < $1.sequence }
    }

    init?(erased: WorldStateComponentValue) {
        guard case let .activeEffects(value) = erased else { return nil }
        self = value
    }

    var isEmpty: Bool {
        effects.isEmpty
    }

    /// The sequence number the next application on this actor gets.
    ///
    /// One past the highest in use rather than a count, so dispelling the only
    /// effect and applying another cannot reuse a number a save still refers
    /// to.
    var nextSequence: UInt64 {
        (effects.map(\.sequence).max() ?? 0) &+ 1
    }

    // MARK: - Queries

    /// Whether any effect on this actor is an application of `effect`.
    ///
    /// The shape `HasMagicEffect` needs (issue 19.11 registers the condition
    /// function and the Papyrus native; this answers them).
    func hasEffect(_ effect: ReferenceKey) -> Bool {
        effects.contains { $0.effect == effect }
    }

    /// Every effect applied by one source record — what a script asking
    /// "is this potion still working" needs.
    func effects(from source: ActiveEffectSource) -> [ActiveEffect] {
        effects.filter { $0.source == source }
    }

    /// Every effect acting on one actor value, which is what a readout of a
    /// single value's contributors lists.
    func effects(affecting index: Int32) -> [ActiveEffect] {
        effects.filter { effect in effect.values.contains { $0.index == index } }
    }

    /// The total each actor value's temporary modifier slot should hold for
    /// this actor, keyed by index.
    ///
    /// This is the authority the save relies on: `AVOV` deliberately does not
    /// persist the temporary modifier, so after a load the slot is re-derived
    /// from here rather than read back off disk twice.
    var ownedModifiers: [Int32: Float] {
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
    func adding(_ effect: ActiveEffect) -> ActiveEffectState {
        var updated = effects.filter { $0.sequence != effect.sequence }
        updated.append(effect)
        return ActiveEffectState(effects: updated)
    }

    /// This state with every effect in `replacements` written over the effect
    /// that shares its sequence, and everything else left alone.
    func replacing(_ replacements: [ActiveEffect]) -> ActiveEffectState {
        guard !replacements.isEmpty else { return self }
        var bySequence: [UInt64: ActiveEffect] = [:]
        for effect in replacements {
            bySequence[effect.sequence] = effect
        }
        return ActiveEffectState(effects: effects.map { bySequence[$0.sequence] ?? $0 })
    }

    /// This state without the effects whose sequences `sequences` names.
    func removing(sequences: Set<UInt64>) -> ActiveEffectState {
        guard !sequences.isEmpty else { return self }
        return ActiveEffectState(effects: effects.filter { !sequences.contains($0.sequence) })
    }

    /// This state without every effect `predicate` selects — the general shape
    /// `Dispel` and the cure archetypes both take.
    func removing(where predicate: (ActiveEffect) -> Bool) -> ActiveEffectState {
        ActiveEffectState(effects: effects.filter { !predicate($0) })
    }

    /// Every effect whose duration has run out.
    var expired: [ActiveEffect] {
        effects.filter(\.isExpired)
    }
}

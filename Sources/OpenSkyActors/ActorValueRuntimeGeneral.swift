// Read and write any of the 164 actor values by index. Every value stores a base
// offset plus three modifiers; a primary keeps its current value in
// `ActorValueState.current`, so its damage slot stays unwritten. A maximum change
// moves the current value too: 100/100 modified by -10 is 90/90
// (<https://ck.uesp.net/wiki/ModActorValue_-_Actor>). See docs/engine/actor-value-store.md.

import Foundation
import OpenSkyActorsInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldState

extension ActorValueRuntime {
    // MARK: - Reading

    /// What `GetActorValue` reports for `index`: the stored current value for a
    /// primary, and base plus modifiers for everything else.
    ///
    /// - Returns: nil only for an index outside the vanilla table. Every value
    ///   the table names answers, falling back to its documented baseline.
    public func value(at index: Int32, on holder: ActorValueHolder) -> Float? {
        if let kind = ActorValueIdentity.kind(at: index) {
            return current(of: holder)[kind]
        }
        return entry(at: index, on: holder)?.current
    }

    /// What `GetBaseActorValue` reports for `index`: the base value, which is
    /// what the records author plus whatever an explicit base write moved it
    /// by, and never a modifier.
    public func baseValue(at index: Int32, on holder: ActorValueHolder) -> Float? {
        entry(at: index, on: holder)?.base
    }

    /// `GetActorValuePercentage`: current over maximum, clamped to 0...1. A primary uses
    /// its effective maximum (its bar); others use their base. A zero or negative
    /// denominator reads 0.
    public func fraction(at index: Int32, on holder: ActorValueHolder) -> Float? {
        guard let value = value(at: index, on: holder) else { return nil }
        let ceiling: Float? = if let kind = ActorValueIdentity.kind(at: index) {
            maximums(of: holder)[kind]
        } else {
            baseValue(at: index, on: holder)
        }
        guard let ceiling else { return nil }
        guard ceiling.isFinite, ceiling > 0, value.isFinite else { return 0 }
        return min(max(0, value / ceiling), 1)
    }

    /// `index`'s whole entry — base and all three modifiers — or nil for an
    /// index outside the table.
    public func entry(at index: Int32, on holder: ActorValueHolder) -> ActorValueEntry? {
        guard let base = baseline(of: holder).base(at: index) else { return nil }
        return state(of: holder).entry(at: index, baseline: base)
    }

    /// Every value `holder` has moved off its baseline, resolved against that
    /// baseline — the shape `ActorConditionState` and `PapyrusActorState`
    /// carry, so a snapshot answers exactly what a live read would.
    public func resolvedEntries(of holder: ActorValueHolder) -> [Int32: ActorValueEntry] {
        let baseline = baseline(of: holder)
        return state(of: holder).overrides.reduce(into: [:]) { table, stored in
            guard let base = baseline.base(at: stored.key) else { return }
            table[stored.key] = stored.value.resolved(baseline: base)
        }
    }

    // MARK: - Mutating

    /// Takes `amount` off `index`, floored at zero: off the current value for a primary,
    /// through the damage modifier otherwise. Returns false only for a bad index.
    @discardableResult
    public func damage(at index: Int32, by amount: Float, on holder: ActorValueHolder) -> Bool {
        if let kind = ActorValueIdentity.kind(at: index) {
            damage(kind, by: amount, on: holder)
            return true
        }
        return update(index, on: holder) { $0.damaging(by: amount) }
    }

    /// Adds `amount` back to `index`, capped at its maximum for a primary and
    /// at "no damage" for everything else.
    ///
    /// - Returns: false only for an index outside the table.
    @discardableResult
    public func restore(at index: Int32, by amount: Float, on holder: ActorValueHolder) -> Bool {
        if let kind = ActorValueIdentity.kind(at: index) {
            restore(kind, by: amount, on: holder)
            return true
        }
        return update(index, on: holder) { $0.restoring(by: amount) }
    }

    /// Sets `index` outright: current value for a primary, base otherwise. The dev and
    /// console path; scripts use `setBase(at:to:on:)`. Returns false only for a bad index.
    @discardableResult
    public func setValue(at index: Int32, to value: Float, on holder: ActorValueHolder) -> Bool {
        if let kind = ActorValueIdentity.kind(at: index) {
            set(kind, to: value, on: holder)
            return true
        }
        return update(index, on: holder) { $0.settingBase(value) }
    }

    /// Sets the base and keeps modifiers, as `SetActorValue` does
    /// (<https://ck.uesp.net/wiki/SetActorValue_-_Actor>). Stored as an offset from the
    /// baseline. Returns false only for a bad index.
    @discardableResult
    public func setBase(at index: Int32, to value: Float, on holder: ActorValueHolder) -> Bool {
        update(index, on: holder) { $0.settingBase(value) }
    }

    /// Raises the base by `delta`, as skill advances and attribute picks do. It rides on
    /// top of the derived value, so a level-up still adds. Returns false for a bad index.
    @discardableResult
    public func incrementBase(
        at index: Int32,
        by delta: Float,
        on holder: ActorValueHolder
    ) -> Bool {
        guard ActorValueIdentity.isVanilla(index: index) else { return false }
        // A zero or non-finite delta is a write that says nothing, not a miss:
        // the index named an actor value, so the caller is not the one to fix.
        guard delta.isFinite, delta != 0 else { return true }
        return updateOverride(index, on: holder) { $0.addingBaseOffset(delta) }
    }

    /// Raises one of the eighteen skills' base by `delta`. Separate from `incrementBase`,
    /// so an off-by-one index fails loudly. Returns false for a non-skill index.
    @discardableResult
    public func advanceSkill(
        at index: Int32,
        by delta: Float,
        on holder: ActorValueHolder
    ) -> Bool {
        guard ActorValueIdentity.isSkill(index: index) else { return false }
        return incrementBase(at: index, by: delta, on: holder)
    }

    /// Adds `delta` to a modifier slot, as effects and `ModActorValue` do. Primaries too,
    /// so Fortify Health raises the ceiling. Returns false only for a bad index.
    @discardableResult
    public func addModifier(
        _ delta: Float,
        to modifier: ActorValueModifier,
        at index: Int32,
        on holder: ActorValueHolder
    ) -> Bool {
        update(index, on: holder) { $0.adding(delta, to: modifier) }
    }

    /// Sets one of `index`'s modifier slots outright.
    ///
    /// - Returns: false by the same rule `addModifier` answers false.
    @discardableResult
    public func setModifier(
        _ value: Float,
        for modifier: ActorValueModifier,
        at index: Int32,
        on holder: ActorValueHolder
    ) -> Bool {
        update(index, on: holder) { $0.setting(modifier, to: value) }
    }

    /// Forces the current value to `value` through the permanent modifier, as
    /// `ForceActorValue` does: base 125 forced to 0 gives -125
    /// (<https://ck.uesp.net/wiki/ForceActorValue_-_Actor>). Returns false for a bad index.
    @discardableResult
    public func forceValue(at index: Int32, to value: Float, on holder: ActorValueHolder) -> Bool {
        // A non-finite target changes nothing, by the rule `incrementBase`
        // states: the index was fine, the number was not.
        guard value.isFinite else { return ActorValueIdentity.isVanilla(index: index) }
        return update(index, on: holder) { entry in
            entry.setting(
                .permanent,
                to: value - entry.base - entry.temporary - entry.damage
            )
        }
    }

    // MARK: - Private

    /// Applies `change` to `index`'s entry and stores it through `store.set`. An unchanged
    /// state writes nothing, so a rejected mutation does not mark a clean actor dirty.
    private func update(
        _ index: Int32,
        on holder: ActorValueHolder,
        _ change: (ActorValueEntry) -> ActorValueEntry
    ) -> Bool {
        let baseline = baseline(of: holder)
        guard let base = baseline.base(at: index) else { return false }
        let state = state(of: holder)
        guard let entry = state.entry(at: index, baseline: base) else { return false }
        return write(
            state.setting(change(entry), at: index, baseline: base),
            over: state,
            at: index,
            derived: baseline.maximums,
            on: holder
        )
    }

    /// The same write for a change stated against the stored override rather
    /// than against the resolved entry, which is what a base *increment* is:
    /// adding to an offset needs no baseline and cannot drift through one.
    private func updateOverride(
        _ index: Int32,
        on holder: ActorValueHolder,
        _ change: (ActorValueOverride) -> ActorValueOverride
    ) -> Bool {
        let state = state(of: holder)
        return write(
            state.setting(change(state.override(at: index)), at: index),
            over: state,
            at: index,
            derived: baseline(of: holder).maximums,
            on: holder
        )
    }

    /// Stores `updated`, first carrying a primary's current value along with
    /// however much its maximum moved.
    private func write(
        _ updated: ActorValueState,
        over state: ActorValueState,
        at index: Int32,
        derived: ActorValues,
        on holder: ActorValueHolder
    ) -> Bool {
        var updated = updated
        if let kind = ActorValueIdentity.kind(at: index) {
            updated = Self.carryingCurrent(kind, from: state, to: updated, derived: derived)
        }
        guard updated != state else { return true }
        store.set(updated, for: holder.key, in: holder.cell)
        return true
    }

    /// `updated` with a primary's current value moved by its maximum's change, then
    /// clamped: 100/100 at -10 is 90/90, and 90/100 is 80/90, so damage survives.
    private static func carryingCurrent(
        _ kind: ActorValueKind,
        from state: ActorValueState,
        to updated: ActorValueState,
        derived: ActorValues
    ) -> ActorValueState {
        let before = maximums(derived: derived, state: state)[kind]
        let after = maximums(derived: derived, state: updated)[kind]
        guard before != after else { return updated }
        var current = updated.current
        current[kind] = min(max(0, current[kind] + after - before), after)
        return ActorValueState(current: current, overrides: updated.overrides)
    }
}

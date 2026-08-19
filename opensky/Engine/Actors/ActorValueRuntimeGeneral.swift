// The index-addressed actor-value mutation surface (issue #468, roadmap item
// 19.5; base overrides for the primaries added by issue #496, item 20.3):
// reading and writing any of the 164 vanilla actor values by index.
//
// A satellite of `ActorValueRuntime.swift` rather than more of it, following
// the same split rule the renderer passes do: that file holds the primary
// surface and regeneration, and is at its size shape.
//
// ## One rule decides everything here
//
// Every vanilla index is stored the same way — a base *offset* on top of the
// re-derived baseline, plus three modifier slots — and the three primaries are
// no longer an exception to it. What is still special about a primary is only
// where its *current* value lives: in `ActorValueState.current`, as a number,
// rather than in a damage modifier. So:
//
// * a read of a primary's current value answers that number;
// * a read of a primary's base answers the re-derived maximum plus its offset;
// * a write that moves a primary's maximum moves the current value with it,
//   which is what "ModActorValue ... adjusts the maximum value for the AV,
//   while DamageActorValue or RestoreActorValue only adjust the current value"
//   requires (<https://ck.uesp.net/wiki/ModActorValue_-_Actor>): an actor at
//   100 health that is modified by -10 ends at 90/90, not at 100/90;
// * the damage *slot* stays unwritten for a primary, because its damage is
//   already the gap between the current value and the maximum.
//
// An index outside the table is the one answer that is still a miss, and nil is
// what the condition and Papyrus tallies count.
//
// Documented in docs/engine/actor-values.md.

import Foundation

extension ActorValueRuntime {
    // MARK: - Reading

    /// What `GetActorValue` reports for `index`: the stored current value for a
    /// primary, and base plus modifiers for everything else.
    ///
    /// - Returns: nil only for an index outside the vanilla table. Every value
    ///   the table names answers, falling back to its documented baseline.
    func value(at index: Int32, on holder: ActorValueHolder) -> Float? {
        if let kind = ActorValueIdentity.kind(at: index) {
            return current(of: holder)[kind]
        }
        return entry(at: index, on: holder)?.current
    }

    /// What `GetBaseActorValue` reports for `index`: the base value, which is
    /// what the records author plus whatever an explicit base write moved it
    /// by, and never a modifier.
    func baseValue(at index: Int32, on holder: ActorValueHolder) -> Float? {
        entry(at: index, on: holder)?.base
    }

    /// What `GetActorValuePercentage` reports: the current value over the
    /// maximum, clamped to 0 ... 1.
    ///
    /// A primary divides by its effective maximum rather than by its base,
    /// because that is the number its bar is drawn against and a fortified
    /// actor at full health is at full health. Every other value has no
    /// separate maximum, so its base is the ceiling.
    ///
    /// A zero or negative denominator reads as 0 rather than dividing, which is
    /// the rule `ActorValues.fractions(of:)` already applies to the HUD meters.
    func fraction(at index: Int32, on holder: ActorValueHolder) -> Float? {
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
    func entry(at index: Int32, on holder: ActorValueHolder) -> ActorValueEntry? {
        guard let base = baseline(of: holder).base(at: index) else { return nil }
        return state(of: holder).entry(at: index, baseline: base)
    }

    /// Every value `holder` has moved off its baseline, resolved against that
    /// baseline — the shape `ActorConditionState` and `PapyrusActorState`
    /// carry, so a snapshot answers exactly what a live read would.
    func resolvedEntries(of holder: ActorValueHolder) -> [Int32: ActorValueEntry] {
        let baseline = baseline(of: holder)
        return state(of: holder).overrides.reduce(into: [:]) { table, stored in
            guard let base = baseline.base(at: stored.key) else { return }
            table[stored.key] = stored.value.resolved(baseline: base)
        }
    }

    // MARK: - Mutating

    /// Takes `amount` off `index`, floored at zero.
    ///
    /// A primary takes it off its current value; every other actor value takes
    /// it through the damage modifier, so its base survives the blow and a
    /// later restore can undo exactly what was done.
    ///
    /// - Returns: false only for an index outside the table.
    @discardableResult
    func damage(at index: Int32, by amount: Float, on holder: ActorValueHolder) -> Bool {
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
    func restore(at index: Int32, by amount: Float, on holder: ActorValueHolder) -> Bool {
        if let kind = ActorValueIdentity.kind(at: index) {
            restore(kind, by: amount, on: holder)
            return true
        }
        return update(index, on: holder) { $0.restoring(by: amount) }
    }

    /// Sets `index` outright: the current value for a primary, and the base
    /// value for everything else.
    ///
    /// The dev-control and console path, which is why a primary lands on the
    /// current value here: a gate that asks for exactly 40 health means the
    /// bar, not the ceiling. `setBase(at:to:on:)` is the scripting path.
    ///
    /// - Returns: false only for an index outside the table.
    @discardableResult
    func setValue(at index: Int32, to value: Float, on holder: ActorValueHolder) -> Bool {
        if let kind = ActorValueIdentity.kind(at: index) {
            set(kind, to: value, on: holder)
            return true
        }
        return update(index, on: holder) { $0.settingBase(value) }
    }

    /// Sets `index`'s base value outright, leaving every modifier intact —
    /// `SetActorValue`'s effect: "Sets the base value specified actor value on
    /// the actor to the passed-in value. Any modifiers are left intact."
    /// (<https://ck.uesp.net/wiki/SetActorValue_-_Actor>)
    ///
    /// Stored as the distance from the re-derived baseline rather than as the
    /// number itself, so a later level change or load-order change moves the
    /// value and this write still says exactly what it said.
    ///
    /// - Returns: false only for an index outside the table.
    @discardableResult
    func setBase(at index: Int32, to value: Float, on holder: ActorValueHolder) -> Bool {
        update(index, on: holder) { $0.settingBase(value) }
    }

    /// Raises `index`'s base by `delta`, which is what a skill advance and an
    /// attribute pick both do (items 20.5 and 20.6).
    ///
    /// The increment survives re-derivation and composes with it: a skill
    /// trained by five points is five points above whatever the records now
    /// author, so a level-up that raises the derived skill still lands on top
    /// of the training instead of replacing it.
    ///
    /// - Returns: false only for an index outside the table.
    @discardableResult
    func incrementBase(at index: Int32, by delta: Float, on holder: ActorValueHolder) -> Bool {
        guard ActorValueIdentity.isVanilla(index: index) else { return false }
        // A zero or non-finite delta is a write that says nothing, not a miss:
        // the index named an actor value, so the caller is not the one to fix.
        guard delta.isFinite, delta != 0 else { return true }
        return updateOverride(index, on: holder) { $0.addingBaseOffset(delta) }
    }

    /// Raises one of the eighteen skills' base by `delta` — the entry point
    /// item 20.5's skill advancement writes through.
    ///
    /// A separate name rather than a comment on `incrementBase` because the
    /// guard is the point: a skill advance that lands on `Aggression` because a
    /// caller had an off-by-one index is a bug that should fail loudly at the
    /// one call site that only ever means a skill.
    ///
    /// - Returns: false for every index that is not one of the eighteen skills.
    @discardableResult
    func advanceSkill(at index: Int32, by delta: Float, on holder: ActorValueHolder) -> Bool {
        guard ActorValueIdentity.isSkill(index: index) else { return false }
        return incrementBase(at: index, by: delta, on: holder)
    }

    /// Adds `delta` to one of `index`'s modifier slots, which is how an effect
    /// applies and removes itself (issue 19.6) and how `ModActorValue` writes.
    ///
    /// Answers for a primary too since item 20.3, so a Fortify Health effect
    /// raises the bar's ceiling instead of being dropped.
    ///
    /// - Returns: false only for an index outside the table.
    @discardableResult
    func addModifier(
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
    func setModifier(
        _ value: Float,
        for modifier: ActorValueModifier,
        at index: Int32,
        on holder: ActorValueHolder
    ) -> Bool {
        update(index, on: holder) { $0.setting(modifier, to: value) }
    }

    /// Forces `index`'s current value to `value` by moving its permanent
    /// modifier, which is what `ForceActorValue` documents:
    ///
    /// "this function modifies the 'permanent modifier' described in the Actor
    /// Value documentation, and that affects how the current value is computed.
    /// If an actor has a base health of 125 and you force their health to 0,
    /// then the permanent modifier will be set to -125, and their current
    /// health will become 0. If you then set the base health to 150, they will
    /// still have a permanent modifier of -125, so their current health will
    /// instantly become 25 (150 - 125)."
    /// (<https://ck.uesp.net/wiki/ForceActorValue_-_Actor>)
    ///
    /// The permanent modifier is therefore whatever makes the current value
    /// come out at `value` against everything that is not permanent — which is
    /// the wiki's own `-125` in an actor carrying nothing else.
    ///
    /// - Returns: false only for an index outside the table.
    @discardableResult
    func forceValue(at index: Int32, to value: Float, on holder: ActorValueHolder) -> Bool {
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

    /// Applies `change` to `index`'s resolved entry and stores the result.
    ///
    /// Writes through `store.set` exactly as the primary path does, so a
    /// script's resistance change lands in the journal, the dirty counts and
    /// the save like a sword's damage does. A change that leaves the state
    /// equal writes nothing, which is what stops a rejected mutation from
    /// materializing a baseline and marking a clean reference dirty.
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

    /// `updated` with one primary's current value moved by the same amount its
    /// maximum moved, then pulled inside the new maximum.
    ///
    /// This is the whole of the documented "adjusts the maximum value for the
    /// AV" behaviour: an actor at 100/100 modified by -10 reads 90/90, and one
    /// at 90/100 reads 80/90 — the damage it was carrying survives the change
    /// rather than being healed or doubled by it.
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

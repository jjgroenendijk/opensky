// The general actor-value mutation surface (issue #468, roadmap item 19.5):
// reading and writing any of the 164 vanilla actor values by index, on top of
// the three primaries `ActorValueRuntime` already stores by kind.
//
// A satellite of `ActorValueRuntime.swift` rather than more of it, following
// the same split rule the renderer passes do: that file holds the primary
// surface and regeneration, and is at its size shape.
//
// ## One rule decides everything here
//
// An index that names one of the three primaries is routed to the typed path,
// unchanged. Every other vanilla index goes to `ActorValueState`'s general
// table. Nothing else in the engine has to know which is which — a caller with
// an index calls the same method either way, and only the failure changes: an
// index outside the table is nil, and nil is what the condition and Papyrus
// tallies now count.
//
// That routing is why the primaries have no base/permanent/temporary/damage
// split. Their current value is stored directly and their maximum is
// re-derived from records on every read, which is 15.3's design and is not
// re-opened here; splitting them would mean re-deriving the HUD, the save, the
// combat damage path and the death latch at once. The consequence is stated
// rather than hidden: `modifier(_:on:at:)` and `setBase` answer nil for health,
// magicka and stamina, and issue 19.6 gets the same three-slot model for the
// other 161 values today and for the primaries when a base-override store
// exists.
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

    /// What `GetBaseActorValue` reports for `index`: the re-derived maximum for
    /// a primary, and the stored base for everything else.
    func baseValue(at index: Int32, on holder: ActorValueHolder) -> Float? {
        if let kind = ActorValueIdentity.kind(at: index) {
            return baseline(of: holder).maximums[kind]
        }
        return entry(at: index, on: holder)?.base
    }

    /// What `GetActorValuePercentage` reports: the current value over the base,
    /// clamped to 0 ... 1.
    ///
    /// A zero or negative base reads as 0 rather than dividing, which is the
    /// rule `ActorValues.fractions(of:)` already applies to the HUD meters.
    func fraction(at index: Int32, on holder: ActorValueHolder) -> Float? {
        guard
            let value = value(at: index, on: holder),
            let base = baseValue(at: index, on: holder)
        else { return nil }
        guard base.isFinite, base > 0, value.isFinite else { return 0 }
        return min(max(0, value / base), 1)
    }

    /// `index`'s whole entry — base and all three modifiers — or nil for a
    /// primary and for an index outside the table.
    func entry(at index: Int32, on holder: ActorValueHolder) -> ActorValueEntry? {
        guard let base = baseline(of: holder).base(at: index) else { return nil }
        return state(of: holder).entry(at: index, baseline: base)
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
    /// value for everything else, leaving that value's modifiers intact the way
    /// `SetActorValue` documents.
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

    /// Adds `delta` to one of `index`'s modifier slots, which is how an effect
    /// applies and removes itself (issue 19.6).
    ///
    /// - Returns: false for an index outside the table and for the three
    ///   primaries, which have no modifier slots — see the file header.
    @discardableResult
    func addModifier(
        _ delta: Float,
        to modifier: ActorValueModifier,
        at index: Int32,
        on holder: ActorValueHolder
    ) -> Bool {
        guard ActorValueIdentity.kind(at: index) == nil else { return false }
        return update(index, on: holder) { $0.adding(delta, to: modifier) }
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
        guard ActorValueIdentity.kind(at: index) == nil else { return false }
        return update(index, on: holder) { $0.setting(modifier, to: value) }
    }

    // MARK: - Private

    /// Applies `change` to `index`'s entry and stores the result.
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
        guard let base = baseline(of: holder).base(at: index) else { return false }
        let state = state(of: holder)
        guard let entry = state.entry(at: index, baseline: base) else { return false }
        let updated = state.setting(change(entry), at: index, baseline: base)
        guard updated != state else { return true }
        store.set(updated, for: holder.key, in: holder.cell)
        return true
    }
}

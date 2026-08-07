// Actor-value accounting (issue #194, roadmap item 15.3): the mutation API
// above `WorldStateStore` — damage, restore, regeneration — and the clamping
// that keeps every value inside its re-derived maximum.
//
// A thin layer beside the store rather than methods on it, following the
// `InventoryRuntime` and `QuestRuntime` precedent. The store is the generic
// substrate that knows about keys, components, journalling and snapshots and
// deliberately knows nothing about records; actor values need
// `ActorValueBaselineResolver` for maximums, which does not belong inside it.
// Everything here writes through `WorldStateStore.set(_:for:in:)`, so every
// mutation lands in the journal, in the dirty counts and in the save exactly
// like a script's `Disable()` does.
//
// Headless and AppKit-free: this compiles into `openskycli` and is testable
// without a window. `@MainActor` only because the store it writes to is.
//
// Failure model: nothing here throws. A damage amount that is negative or NaN
// is ignored, an unknown subject falls back to a documented baseline, and every
// write is clamped. Runtime state is not file parsing — there is no malformed
// input to reject, and an actor that cannot be hit because a mutation threw is
// a worse outcome than one that takes a clamped hit.
//
// Documented in docs/engine/actor-values.md.

import Foundation

/// Reads and mutates actor values on top of a `WorldStateStore`.
@MainActor
struct ActorValueRuntime {
    /// Simulation step regeneration advances in, matching the Papyrus VM's
    /// fixed step so that a frame drives both the same way. 1/60 s.
    static let fixedStepSeconds = 1.0 / 60

    /// Most whole steps one `advance(delta:)` runs, so a multi-second stall
    /// cannot spend minutes regenerating in a single frame.
    static let maximumStepsPerAdvance = 8

    let store: WorldStateStore
    let baselines: ActorValueBaselineResolver

    // MARK: - Reading

    /// `holder`'s maximums and regen rates, re-derived from plugin data.
    func baseline(of holder: ActorValueHolder) -> ActorValueBaseline {
        baselines.baseline(for: holder.subject)
    }

    /// `holder`'s effective state: its runtime component when it has one, a
    /// full baseline when it does not.
    func state(of holder: ActorValueHolder) -> ActorValueState {
        store.component(ActorValueState.self, for: holder.key)
            ?? ActorValueState.baseline(maximums: baseline(of: holder).maximums)
    }

    /// Whether `holder` has been touched at runtime, as opposed to still
    /// reading a full baseline.
    func hasRuntimeState(_ holder: ActorValueHolder) -> Bool {
        store.component(ActorValueState.self, for: holder.key) != nil
    }

    /// `holder`'s current values.
    func current(of holder: ActorValueHolder) -> ActorValues {
        state(of: holder).current
    }

    /// `holder`'s current values as fractions of its maximums, which is the
    /// shape the HUD meters take.
    func fractions(of holder: ActorValueHolder) -> ActorValues {
        current(of: holder).fractions(of: baseline(of: holder).maximums)
    }

    /// Whether `holder` is at zero health. The flag item 15.6 consumes; this
    /// layer does not act on it.
    func hasZeroHealth(_ holder: ActorValueHolder) -> Bool {
        state(of: holder).hasZeroHealth
    }

    // MARK: - Mutating

    /// Takes `amount` off one of `holder`'s values, floored at zero.
    ///
    /// The first mutation materializes the baseline into the component, so an
    /// actor with 120 maximum health that takes 20 damage ends up with a
    /// component holding 100 rather than a delta holding -20.
    ///
    /// - Returns: the state as stored afterwards.
    @discardableResult
    func damage(
        _ kind: ActorValueKind,
        by amount: Float,
        on holder: ActorValueHolder
    ) -> ActorValueState {
        write(state(of: holder).damaging(kind, by: amount), for: holder)
    }

    /// Adds `amount` to one of `holder`'s values, capped at its maximum.
    ///
    /// - Returns: the state as stored afterwards.
    @discardableResult
    func restore(
        _ kind: ActorValueKind,
        by amount: Float,
        on holder: ActorValueHolder
    ) -> ActorValueState {
        let maximum = baseline(of: holder).maximums[kind]
        return write(
            state(of: holder).restoring(kind, by: amount, maximum: maximum),
            for: holder
        )
    }

    /// Sets one value outright, clamped to `0 ... maximum`. What a dev control
    /// and a console line drive; ordinary gameplay goes through `damage` and
    /// `restore`.
    ///
    /// - Returns: the state as stored afterwards.
    @discardableResult
    func set(
        _ kind: ActorValueKind,
        to value: Float,
        on holder: ActorValueHolder
    ) -> ActorValueState {
        var updated = current(of: holder)
        updated[kind] = value
        return write(
            ActorValueState(current: updated.clamped(to: baseline(of: holder).maximums)),
            for: holder
        )
    }

    /// Refills every value to its maximum.
    ///
    /// - Returns: the state as stored afterwards.
    @discardableResult
    func restoreAll(on holder: ActorValueHolder) -> ActorValueState {
        write(
            ActorValueState.baseline(maximums: baseline(of: holder).maximums),
            for: holder
        )
    }

    // MARK: - Regeneration

    /// Advances regeneration by exactly one fixed step for every holder in
    /// `holders`.
    ///
    /// Deterministic in two senses the acceptance gate cares about. The order
    /// is the caller's `ReferenceKey` order — `regeneration(over:)` sorts, so a
    /// set of actors regenerates identically whichever order they were
    /// collected in. And the amount is a pure function of the step and the
    /// baseline, with no accumulated float drift per actor: each step adds
    /// `maximum * percent / 100 * step`.
    ///
    /// Health does not regenerate at zero. An actor at zero health is dead or
    /// in bleedout, and both are 15.6's to decide; silently healing one back to
    /// life here would make that decision on 15.6's behalf.
    ///
    /// - Returns: the holders whose stored state actually changed.
    @discardableResult
    func stepRegeneration(over holders: [ActorValueHolder]) -> [ActorValueHolder] {
        regenerate(over: holders, seconds: Self.fixedStepSeconds)
    }

    /// Accumulates a wall delta and runs whole fixed steps only, capped at
    /// `maximumStepsPerAdvance`; the remainder carries in `accumulator`.
    ///
    /// A zero delta advances nothing, regenerates nothing, and is safe to call
    /// every frame — the established menu-pause rule, which reaches this layer
    /// as delta 0 exactly as it reaches the Papyrus VM. A negative or
    /// non-finite delta is treated the same way rather than run backwards.
    ///
    /// The accumulator is the caller's, not the runtime's, because this type is
    /// a struct over a shared store: two of them may exist at once and a
    /// per-instance accumulator would silently split the simulation in half.
    ///
    /// - Returns: how many whole steps ran.
    @discardableResult
    func advance(
        delta: Float,
        accumulator: inout Double,
        over holders: [ActorValueHolder]
    ) -> Int {
        guard delta.isFinite, delta > 0 else { return 0 }
        accumulator += Double(delta)
        var steps = 0
        while accumulator >= Self.fixedStepSeconds, steps < Self.maximumStepsPerAdvance {
            accumulator -= Self.fixedStepSeconds
            stepRegeneration(over: holders)
            steps += 1
        }
        // After a capped hitch, keep at most one more burst of debt so a long
        // stall cannot spiral into minutes of catch-up.
        accumulator = min(
            accumulator,
            Self.fixedStepSeconds * Double(Self.maximumStepsPerAdvance)
        )
        return steps
    }

    // MARK: - Reset

    /// Drops `holder`'s runtime state, so it re-derives a full baseline again.
    /// The component-level counterpart of `WorldStateStore.reset(_:)`.
    ///
    /// - Returns: true when runtime state was actually removed.
    @discardableResult
    func reset(_ holder: ActorValueHolder) -> Bool {
        store.reset(.actorValues, for: holder.key)
    }

    // MARK: - Private

    /// Stores `state`, unless doing so would materialize a baseline that has
    /// not moved.
    ///
    /// The guard matters because `state(of:)` hands back a full baseline for an
    /// untouched actor: without it, a rejected mutation — a zero damage, a NaN
    /// restore — would write that baseline straight back and mark a reference
    /// dirty that nothing had touched. An actor with a component already writes
    /// unconditionally, because `WorldStateStore.set` is itself a no-op for an
    /// unchanged value.
    private func write(
        _ state: ActorValueState,
        for holder: ActorValueHolder
    ) -> ActorValueState {
        guard hasRuntimeState(holder) || state != self.state(of: holder) else {
            return state
        }
        store.set(state, for: holder.key, in: holder.cell)
        return state
    }

    /// One regeneration tick of `seconds` over every holder, in `ReferenceKey`
    /// order.
    private func regenerate(
        over holders: [ActorValueHolder],
        seconds: Double
    ) -> [ActorValueHolder] {
        guard seconds > 0 else { return [] }
        var changed: [ActorValueHolder] = []
        for holder in holders.sorted(by: { $0.key < $1.key }) {
            let baseline = baseline(of: holder)
            let state = state(of: holder)
            var updated = state.current
            for kind in ActorValueKind.allCases {
                let maximum = baseline.maximums[kind]
                let percent = baseline.regenPercentPerSecond[kind]
                guard maximum.isFinite, maximum > 0, percent.isFinite, percent > 0 else {
                    continue
                }
                if kind == .health, updated.health <= 0 {
                    continue
                }
                let gain = maximum * percent / 100 * Float(seconds)
                updated[kind] = min(maximum, updated[kind] + gain)
            }
            guard updated != state.current else { continue }
            store.set(ActorValueState(current: updated), for: holder.key, in: holder.cell)
            changed.append(holder)
        }
        return changed
    }
}

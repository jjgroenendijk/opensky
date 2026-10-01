// Actor-value accounting: damage, restore and regeneration, clamped to the re-derived
// maximum, written through `WorldStateStore.set(_:for:in:)` so it reaches the journal
// and the save. Nothing throws: negative or NaN amounts are ignored and every write is
// clamped. See docs/engine/actor-value-store.md.

import Foundation
import OpenSkyActorsInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldState

/// Reads and mutates actor values on top of a `WorldStateStore`.
@MainActor
public struct ActorValueRuntime: ActorValueAccess {
    public static let fixedStepSeconds = ActorValueStep.fixedStepSeconds
    public static let maximumStepsPerAdvance = ActorValueStep.maximumStepsPerAdvance

    public let store: WorldStateStore
    public let baselines: ActorValueBaselineResolver

    // MARK: - Reading

    /// `holder`'s maximums and regen rates, re-derived from plugin data.
    public func baseline(of holder: ActorValueHolder) -> ActorValueBaseline {
        baselines.baseline(for: holder.subject)
    }

    /// `holder`'s effective state: its runtime component when it has one, a
    /// full baseline when it does not.
    public func state(of holder: ActorValueHolder) -> ActorValueState {
        store.component(ActorValueState.self, for: holder.key)
            ?? ActorValueState.baseline(maximums: baseline(of: holder).maximums)
    }

    /// `holder`'s effective maximums: re-derived each time, plus base offsets and the
    /// permanent and temporary modifiers. Damage is not included: it lowers the current
    /// value only (<https://ck.uesp.net/wiki/ModActorValue_-_Actor>).
    public func maximums(of holder: ActorValueHolder) -> ActorValues {
        Self.maximums(derived: baseline(of: holder).maximums, state: state(of: holder))
    }

    /// The same maximums for a caller that already holds both halves, so the
    /// regeneration loop does not re-read the store once per primary.
    ///
    /// Floored at zero the way every derived maximum is: the game has no
    /// concept of a negative maximum, and one would make every fraction the HUD
    /// asks for meaningless.
    public static func maximums(derived: ActorValues, state: ActorValueState) -> ActorValues {
        var values = ActorValues.zero
        for kind in ActorValueKind.allCases {
            let index = ActorValueIdentity.index(of: kind)
            values[kind] = max(0, derived[kind] + state.override(at: index).maximumOffset)
        }
        return values
    }

    /// Whether `holder` has been touched at runtime, as opposed to still
    /// reading a full baseline.
    public func hasRuntimeState(_ holder: ActorValueHolder) -> Bool {
        store.component(ActorValueState.self, for: holder.key) != nil
    }

    /// `holder`'s current values.
    public func current(of holder: ActorValueHolder) -> ActorValues {
        state(of: holder).current
    }

    /// `holder`'s current values as fractions of its maximums, which is the
    /// shape the HUD meters take.
    public func fractions(of holder: ActorValueHolder) -> ActorValues {
        current(of: holder).fractions(of: maximums(of: holder))
    }

    /// Whether `holder` is at zero health. Ragdoll and death consume the flag; this layer
    /// does not act on it.
    public func hasZeroHealth(_ holder: ActorValueHolder) -> Bool {
        state(of: holder).hasZeroHealth
    }

    // MARK: - Mutating

    /// Takes `amount` off one of `holder`'s values, floored at zero. The first write
    /// stores the full state (120 - 20 stores 100, not -20).
    /// - Returns: the state as stored afterwards.
    @discardableResult
    public func damage(
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
    public func restore(
        _ kind: ActorValueKind,
        by amount: Float,
        on holder: ActorValueHolder
    ) -> ActorValueState {
        let maximum = maximums(of: holder)[kind]
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
    public func set(
        _ kind: ActorValueKind,
        to value: Float,
        on holder: ActorValueHolder
    ) -> ActorValueState {
        let state = state(of: holder)
        var updated = state.current
        updated[kind] = value
        return write(
            ActorValueState(
                current: updated.clamped(to: maximums(of: holder)),
                overrides: state.overrides
            ),
            for: holder
        )
    }

    /// Refills every value to its maximum.
    ///
    /// - Returns: the state as stored afterwards.
    @discardableResult
    public func restoreAll(on holder: ActorValueHolder) -> ActorValueState {
        // The override table survives a refill: a fortified actor filled to
        // the top is full at its fortified maximum, not stripped of the buff.
        write(
            ActorValueState(
                current: maximums(of: holder),
                overrides: state(of: holder).overrides
            ),
            for: holder
        )
    }

    // MARK: - Regeneration

    /// Advances regeneration one fixed step for each holder, in `ReferenceKey` order,
    /// adding `maximum * percent / 100 * step` with no drift. Health at zero does not
    /// regenerate; death decides that. Returns the holders that changed.
    @discardableResult
    public func stepRegeneration(over holders: [ActorValueHolder]) -> [ActorValueHolder] {
        regenerate(over: holders, seconds: Self.fixedStepSeconds)
    }

    /// Runs whole fixed steps from a wall delta, capped at `maximumStepsPerAdvance`; the
    /// rest carries in the caller's `accumulator`. Zero, negative or non-finite runs
    /// nothing, which is the menu pause. Returns the step count.
    @discardableResult
    public func advance(
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
    public func reset(_ holder: ActorValueHolder) -> Bool {
        store.reset(.actorValues, for: holder.key)
    }

    // MARK: - Private

    /// Stores `state` unless it is an unmoved baseline, so a rejected mutation does not
    /// mark a clean actor dirty. An existing component always writes; `set` skips
    /// equal values.
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
            let maximums = Self.maximums(derived: baseline.maximums, state: state)
            var updated = state.current
            for kind in ActorValueKind.allCases {
                let maximum = maximums[kind]
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
            // Keep the override table in the write, or 60 regeneration writes a second
            // would drop a magic effect's temporary modifier.
            store.set(
                ActorValueState(current: updated, overrides: state.overrides),
                for: holder.key,
                in: holder.cell
            )
            changed.append(holder)
        }
        return changed
    }

    public init(store: WorldStateStore, baselines: ActorValueBaselineResolver) {
        self.store = store
        self.baselines = baselines
    }
}

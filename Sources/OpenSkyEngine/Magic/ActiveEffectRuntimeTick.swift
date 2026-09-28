// Ticking active effects (issue #469, roadmap item 19.6): the fixed-step
// advance, the whole-second pay-out a `perSecond` effect owes, and expiry.
//
// A satellite of `ActiveEffectRuntime.swift` rather than more of it, following
// the same split rule `ActorValueRuntimeGeneral.swift` does: that file owns
// applying, dispelling and reading, and is at its size shape.
//
// Documented in docs/engine/magic.md.

import Foundation

extension ActiveEffectRuntime {
    // MARK: - Ticking

    /// Advances every effect on `holders` by exactly one fixed step.
    ///
    /// Deterministic in the two senses the acceptance gate cares about: holders
    /// are advanced in `ReferenceKey` order, and the amount is a pure function
    /// of the step and the stored effect.
    ///
    /// - Returns: how many effects expired.
    @discardableResult
    mutating func step(over holders: [ActorValueHolder]) -> Int {
        tick(over: holders, seconds: Float(Self.fixedStepSeconds))
    }

    /// Accumulates a wall delta and runs whole fixed steps only, capped at
    /// `maximumStepsPerAdvance`; the remainder carries in `accumulator`.
    ///
    /// A zero delta advances nothing, which is the established menu-pause rule:
    /// a paused frame reaches this layer as delta 0 exactly as it reaches the
    /// Papyrus VM and regeneration.
    ///
    /// - Returns: how many whole steps ran.
    @discardableResult
    mutating func advance(
        delta: Float,
        accumulator: inout Double,
        over holders: [ActorValueHolder]
    ) -> Int {
        guard delta.isFinite, delta > 0 else { return 0 }
        accumulator += Double(delta)
        var steps = 0
        while accumulator >= Self.fixedStepSeconds, steps < Self.maximumStepsPerAdvance {
            accumulator -= Self.fixedStepSeconds
            step(over: holders)
            steps += 1
        }
        accumulator = min(
            accumulator,
            Self.fixedStepSeconds * Double(Self.maximumStepsPerAdvance)
        )
        return steps
    }

    // MARK: - Private

    /// One tick of `seconds` over every holder, in `ReferenceKey` order.
    private mutating func tick(over holders: [ActorValueHolder], seconds: Float) -> Int {
        guard seconds > 0 else { return 0 }
        var expiredCount = 0
        for holder in holders.sorted(by: { $0.key < $1.key }) {
            let state = state(of: holder)
            guard !state.isEmpty else { continue }
            var advanced: [ActiveEffect] = []
            advanced.reserveCapacity(state.effects.count)
            for effect in state.effects {
                advanced.append(pay(effect.advanced(by: seconds), on: holder))
            }
            var updated = state.replacing(advanced)
            let expired = updated.expired
            if !expired.isEmpty {
                release(expired, on: holder)
                updated = updated.removing(sequences: Set(expired.map(\.sequence)))
                tally.noteExpired(expired.count)
                expiredCount += expired.count
            }
            write(updated, for: holder)
        }
        return expiredCount
    }

    /// Pays out every whole second a `perSecond` effect owes.
    private mutating func pay(_ effect: ActiveEffect, on holder: ActorValueHolder) -> ActiveEffect {
        let owed = effect.unpaidSeconds
        guard owed > 0 else { return effect }
        for value in effect.values {
            let amount = value.magnitude * Float(owed)
            if effect.isDetrimental {
                values.damage(at: value.index, by: amount, on: holder)
            } else {
                values.restore(at: value.index, by: amount, on: holder)
            }
        }
        tally.noteSecondsPaid(Int(owed))
        return effect.paying(owed)
    }
}

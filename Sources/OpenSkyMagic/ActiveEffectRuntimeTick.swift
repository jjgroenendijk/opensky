// Ticking active effects: the fixed-step advance, `perSecond` payouts, and expiry.
// See docs/engine/magic.md.

import Foundation
import OpenSkyActorsInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface

extension ActiveEffectRuntime {
    // MARK: - Ticking

    /// Advances every effect on `holders` one fixed step, in `ReferenceKey` order.
    /// Returns how many expired.
    @discardableResult
    public mutating func step(over holders: [ActorValueHolder]) -> Int {
        tick(over: holders, seconds: Float(Self.fixedStepSeconds))
    }

    /// Runs whole fixed steps from a wall delta, capped at `maximumStepsPerAdvance`; the
    /// rest carries in `accumulator`. Zero runs nothing (the menu pause). Returns the count.
    @discardableResult
    public mutating func advance(
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
        for holder in holderOrder.sorted(holders, by: \.key) {
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

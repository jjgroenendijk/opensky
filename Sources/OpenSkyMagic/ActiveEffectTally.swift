// What the active-effect runtime did and did not do. Every declined path counts
// here, like `ConditionTally`, so a sweep can assert on the gaps.
// See docs/engine/magic.md.

import Foundation

nonisolated public struct ActiveEffectTally: Equatable, Sendable {
    /// Timed effects that became components on an actor.
    public private(set) var applied = 0
    /// Zero-duration effects applied once and stored nowhere.
    public private(set) var instantApplications = 0
    /// Effects removed because their duration ran out.
    public private(set) var expired = 0
    /// Effects removed by an explicit dispel.
    public private(set) var dispelled = 0
    /// Entries whose CTDA list evaluated false against the target.
    public private(set) var conditionSkipped = 0
    /// Entries whose `MGEF` conditions evaluated false, so the target never got them.
    public private(set) var effectConditionSkipped = 0
    /// Stored effects suspended or resumed by the per-second check of their entry.
    public private(set) var suspended = 0
    public private(set) var resumed = 0
    /// Applications refused because the MGEF sets No Recast and the target
    /// already carries that effect.
    public private(set) var recastRefused = 0
    /// Peak Value Modifier applications where a shared keyword meant one of the
    /// two effects had to go, in either direction.
    public private(set) var peakStackResolved = 0
    /// EFID links that resolved to no MGEF in the load order.
    public private(set) var unresolvedEffect = 0
    /// Whole-second pay-outs a `perSecond` effect made.
    public private(set) var secondsPaid = 0
    /// Why entries produced no application, by reason.
    public private(set) var skips: [MagicEffectPlanFailure: Int] = [:]

    public mutating func note(_ failure: MagicEffectPlanFailure) {
        skips[failure, default: 0] += 1
    }

    public mutating func noteApplied() {
        applied += 1
    }

    public mutating func noteInstant() {
        instantApplications += 1
    }

    public mutating func noteExpired(_ count: Int = 1) {
        expired += count
    }

    public mutating func noteDispelled(_ count: Int = 1) {
        dispelled += count
    }

    public mutating func noteConditionSkipped() {
        conditionSkipped += 1
    }

    public mutating func noteEffectConditionSkipped() {
        effectConditionSkipped += 1
    }

    public mutating func noteSuspension(_ suspended: Bool) {
        if suspended {
            self.suspended += 1
        } else {
            resumed += 1
        }
    }

    public mutating func noteRecastRefused() {
        recastRefused += 1
    }

    public mutating func notePeakStackResolved() {
        peakStackResolved += 1
    }

    public mutating func noteUnresolvedEffect() {
        unresolvedEffect += 1
    }

    public mutating func noteSecondsPaid(_ count: Int) {
        secondsPaid += count
    }
}

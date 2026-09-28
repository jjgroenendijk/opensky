// What the active-effect runtime did and did not do (issue #469, roadmap item
// 19.6).
//
// Every path that declines to apply something increments a bucket here, so the
// ground this milestone does not cover is measured rather than silent. That is
// the same discipline `ConditionTally` and `MagicEffectTally` already follow:
// an unimplemented archetype is a number a sweep can assert on, not a shrug.
//
// Documented in docs/engine/magic.md.

import Foundation

nonisolated struct ActiveEffectTally: Equatable, Sendable {
    /// Timed effects that became components on an actor.
    private(set) var applied = 0
    /// Zero-duration effects applied once and stored nowhere.
    private(set) var instantApplications = 0
    /// Effects removed because their duration ran out.
    private(set) var expired = 0
    /// Effects removed by an explicit dispel.
    private(set) var dispelled = 0
    /// Entries whose CTDA list evaluated false against the target.
    private(set) var conditionSkipped = 0
    /// Applications refused because the MGEF sets No Recast and the target
    /// already carries that effect.
    private(set) var recastRefused = 0
    /// Peak Value Modifier applications where a shared keyword meant one of the
    /// two effects had to go, in either direction.
    private(set) var peakStackResolved = 0
    /// EFID links that resolved to no MGEF in the load order.
    private(set) var unresolvedEffect = 0
    /// Whole-second pay-outs a `perSecond` effect made.
    private(set) var secondsPaid = 0
    /// Why entries produced no application, by reason.
    private(set) var skips: [MagicEffectPlanFailure: Int] = [:]

    /// Everything that was counted as declining to do something.
    var totalSkips: Int {
        skips.values.reduce(0, +) + conditionSkipped + recastRefused + unresolvedEffect
    }

    /// How many entries named one unimplemented archetype.
    func skipCount(_ failure: MagicEffectPlanFailure) -> Int {
        skips[failure] ?? 0
    }

    /// Every unimplemented archetype seen, with its count — the listing a
    /// coverage readout shows.
    var unimplementedArchetypes: [(archetype: MagicEffectArchetype, count: Int)] {
        skips
            .compactMap { failure, count -> (MagicEffectArchetype, Int)? in
                guard case let .unimplementedArchetype(archetype) = failure else { return nil }
                return (archetype, count)
            }
            .sorted { left, right in
                left.1 == right.1
                    ? left.0.description < right.0.description
                    : left.1 > right.1
            }
            .map { (archetype: $0.0, count: $0.1) }
    }

    mutating func note(_ failure: MagicEffectPlanFailure) {
        skips[failure, default: 0] += 1
    }

    mutating func noteApplied() {
        applied += 1
    }

    mutating func noteInstant() {
        instantApplications += 1
    }

    mutating func noteExpired(_ count: Int = 1) {
        expired += count
    }

    mutating func noteDispelled(_ count: Int = 1) {
        dispelled += count
    }

    mutating func noteConditionSkipped() {
        conditionSkipped += 1
    }

    mutating func noteRecastRefused() {
        recastRefused += 1
    }

    mutating func notePeakStackResolved() {
        peakStackResolved += 1
    }

    mutating func noteUnresolvedEffect() {
        unresolvedEffect += 1
    }

    mutating func noteSecondsPaid(_ count: Int) {
        secondsPaid += count
    }
}

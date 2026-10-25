// What a cast loop declined to do, counted rather than swallowed. A plain value the
// readout and tests read. See docs/engine/spellcasting.md.

import Foundation
import OpenSkyFormatsESM

/// Everything the cast loop declined to do, so unimplemented ground is measured
/// rather than silent.
nonisolated public struct CastingTally: Equatable, Sendable {
    public private(set) var castCount = 0
    public private(set) var concentrationSeconds = 0
    public private(set) var failureCounts: [String: Int] = [:]
    /// Spell projectiles launched.
    public private(set) var projectileCount = 0
    /// Casts both hands began together.
    public private(set) var dualCastCount = 0
    /// Casts per delivery kind, so the ground each delivery covers is measured
    /// rather than assumed from the refusal counts alone.
    public private(set) var deliveryCounts: [String: Int] = [:]

    public mutating func noteCast() {
        castCount += 1
    }

    public mutating func noteConcentrationSecond() {
        concentrationSeconds += 1
    }

    public mutating func note(_ failure: SpellCastFailure) {
        failureCounts[failure.describedReason, default: 0] += 1
    }

    public mutating func noteDualCast() {
        dualCastCount += 1
    }

    public mutating func noteProjectile() {
        projectileCount += 1
    }

    public mutating func note(delivery: MagicEffectDelivery) {
        deliveryCounts[delivery.description, default: 0] += 1
    }

    public var failureCount: Int {
        failureCounts.values.reduce(0, +)
    }
}

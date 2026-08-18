// What a cast loop declined to do (issue #470, roadmap item 19.7), counted
// rather than swallowed.
//
// Its own file beside `CasterRuntime.swift` for the reason `ActiveEffectTally`
// is one: the runtime is at the strict-lint length cap, and a tally is a value
// with no behaviour of its own that a panel and a test both read.
//
// Documented in docs/engine/magic.md.

import Foundation

/// Everything the cast loop declined to do, so unimplemented ground is measured
/// rather than silent.
nonisolated struct CastingTally: Equatable, Sendable {
    private(set) var castCount = 0
    private(set) var concentrationSeconds = 0
    private(set) var failureCounts: [String: Int] = [:]
    /// Ability effect entries that carry no duration and so could not be held.
    /// See `applyAbilities(on:)` for why they are counted rather than applied.
    private(set) var unheldAbilityEntries = 0
    /// Spell projectiles launched (issue #471).
    private(set) var projectileCount = 0
    /// Casts per delivery kind, so the ground each delivery covers is measured
    /// rather than assumed from the refusal counts alone.
    private(set) var deliveryCounts: [String: Int] = [:]

    mutating func noteCast() {
        castCount += 1
    }

    mutating func noteConcentrationSecond() {
        concentrationSeconds += 1
    }

    mutating func note(_ failure: SpellCastFailure) {
        failureCounts[failure.describedReason, default: 0] += 1
    }

    mutating func noteUnheldAbilityEntries(_ count: Int) {
        unheldAbilityEntries += count
    }

    mutating func noteProjectile() {
        projectileCount += 1
    }

    mutating func note(delivery: MagicEffectDelivery) {
        deliveryCounts[delivery.description, default: 0] += 1
    }

    /// Deliveries seen, most frequent first, already spelled `kind x count`.
    var deliveryLines: [String] {
        deliveryCounts
            .sorted { ($0.value, $1.key) > ($1.value, $0.key) }
            .map { "\($0.key) x \($0.value)" }
    }

    var failureCount: Int {
        failureCounts.values.reduce(0, +)
    }

    /// Failure reasons, most frequent first, already spelled `reason x count`.
    var failureLines: [String] {
        failureCounts
            .sorted { ($0.value, $1.key) > ($1.value, $0.key) }
            .map { "\($0.key) x \($0.value)" }
    }
}

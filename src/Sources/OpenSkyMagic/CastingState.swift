// Where a cast is: the per-hand state machine and its outcomes. A pure value
// type over a clock. No casting graph is driven yet, so the charge is timed by
// SPIT. UESP's Magic Overview gives the two shapes: concentration, and charge
// then release (<https://en.uesp.net/wiki/Skyrim:Magic_Overview>).
// See docs/engine/spellcasting.md.

import Foundation
public import OpenSkyFormatsESM
public import OpenSkyMagicInterface

/// The two hands of one dual cast.
nonisolated enum DualCastRole: String, Equatable, Sendable {
    case lead
    case partner
}

/// One hand's cast, advanced by time.
///
/// Deliberately not a world-state component: a charge in progress is frame
/// state, and a save that restored one would put the player back mid-cast with
/// magicka already committed. The readied spell persists; the cast does not.
nonisolated public struct SpellCastState: Equatable, Sendable {
    public private(set) var phase = SpellCastPhase.idle
    /// The spell this cast is of, nil while idle.
    public private(set) var spell: ReferenceKey?
    /// Seconds spent charging so far.
    public private(set) var charged: Float = 0
    /// Seconds the concentration has been maintained.
    public private(set) var held: Float = 0
    /// Whole seconds of concentration whose effect application already
    /// happened. Counted rather than derived from `held`, for the reason
    /// `ActiveEffect.paidSeconds` is: repeated small steps must not round into
    /// an extra application.
    private(set) var appliedSeconds: UInt32 = 0
    /// Magicka this cast has taken so far, which for a concentration spell
    /// grows for as long as it runs.
    public private(set) var magickaSpent: Float = 0
    /// True once the input was released but the concentration has not yet
    /// reached the SPIT minimum cast duration.
    public private(set) var isReleasing = false
    /// The hand's part in a dual cast, nil for a single cast. The lead hand runs the
    /// cast; the partner only holds the spell, so the cast pays and applies once.
    private(set) var dualRole: DualCastRole?

    public var isDualCast: Bool {
        dualRole != nil
    }

    mutating func joinDualCast(as role: DualCastRole) {
        dualRole = role
    }

    /// Starts a charge.
    public mutating func beginCharge(_ spell: ReferenceKey) {
        self = SpellCastState()
        phase = .charging
        self.spell = spell
    }

    /// Moves a fully charged fire-and-forget cast to the release window.
    mutating func makeReady() {
        phase = .ready
    }

    /// Moves a fully charged concentration cast to maintenance.
    mutating func beginConcentration() {
        phase = .concentrating
    }

    /// Seconds since the cast began, whatever its phase. A dual cast may join only a
    /// young one.
    private(set) var age: Float = 0

    mutating func addAge(_ delta: Float) {
        age += delta
    }

    mutating func addCharge(_ delta: Float) {
        charged += delta
    }

    mutating func addHeld(_ delta: Float) {
        held += delta
    }

    mutating func noteApplied() {
        appliedSeconds += 1
    }

    mutating func spend(_ magicka: Float) {
        magickaSpent += magicka
    }

    public mutating func requestRelease() {
        isReleasing = true
    }

    /// How close to a whole second counts as one. Sixty 1/60 s steps sum to just
    /// under one second in binary floating point; without this tolerance a
    /// maintained spell would skip an application.
    static let secondTolerance: Float = 0.001

    /// Applications that are due, capped at the steps one advance may run. One at
    /// entry plus one per whole second held, hence `elapsed + 1`.
    func pendingApplications(limit: Int) -> Int {
        let elapsed = UInt32(max(0, held + Self.secondTolerance).rounded(.down))
        let due = elapsed &+ 1
        guard due > appliedSeconds else { return 0 }
        return min(Int(due - appliedSeconds), limit)
    }
}

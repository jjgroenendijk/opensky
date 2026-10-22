// Trespass as the game runs it: a warning when someone first sees the player where
// the owner did not invite them, and a bounty once the grace period ends with the
// player still seen there (UESP "Skyrim:Crime": one warning, then a bounty after
// 30 seconds). An Off Limits cell skips the warning. See docs/engine/crime.md.

import OpenSkyCrimeInterface
import OpenSkyGameData

/// What one trespass tick asks for.
nonisolated public enum TrespassStep: Equatable, Sendable {
    case none
    /// Tell the player to leave; `remaining` is the number of seconds left.
    case warn(remaining: Double)
    case charge
}

/// One stay in one owned cell. Real seconds, not game seconds: the grace period is
/// a wall-clock wait in the game.
nonisolated public struct TrespassWatch: Equatable, Sendable {
    public private(set) var cell: CellSceneLocation?
    /// Seconds since the first warning, or nil before it.
    public private(set) var sinceWarning: Double?
    public private(set) var warnings = 0
    /// `sinceWarning` at the last warning.
    public private(set) var lastWarning: Double = 0
    public private(set) var isCharged = false

    public init() {}

    /// A new cell starts a new stay.
    public mutating func enter(_ location: CellSceneLocation?) {
        self = Self()
        cell = location
    }

    /// One tick of `seconds`. `seen` says whether anyone detects the player now.
    /// `iTrespassWarnings` warnings spread over the grace period; the charge
    /// comes at its end, but no sooner than `fAITrespassWarningTimer` after the last
    /// warning, or at once in an Off Limits cell. Two warnings are at least
    /// `fWarningTimer` apart.
    public mutating func step(
        seconds: Double, seen: Bool, offLimits: Bool, settings: CrimeSettings
    ) -> TrespassStep {
        guard !isCharged else { return .none }
        if let since = sinceWarning {
            sinceWarning = since + max(0, seconds)
        }
        guard seen else { return .none }
        let grace = max(0, settings.trespassGraceSeconds)
        guard !offLimits, let since = sinceWarning else {
            if offLimits {
                isCharged = true
                return .charge
            }
            sinceWarning = 0
            warnings = 1
            return .warn(remaining: grace)
        }
        let callDelay = Double(max(0, settings.trespassCallGuardsSeconds))
        if since >= grace {
            guard since - lastWarning >= callDelay else { return .none }
            isCharged = true
            return .charge
        }
        let count = max(1, settings.trespassWarnings)
        let spaced = lastWarning + Double(max(0, settings.trespassWarningInterval))
        let nextWarning = max(grace * Double(warnings) / Double(count), spaced)
        guard warnings < count, since >= nextWarning, nextWarning < grace else { return .none }
        warnings += 1
        lastWarning = since
        return .warn(remaining: max(grace - since, callDelay))
    }
}

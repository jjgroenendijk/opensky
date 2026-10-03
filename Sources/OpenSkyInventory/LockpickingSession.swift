// The lockpicking minigame as a pure model: pick angle, lock turn, pick health.
// Widths and break times follow UESP "Skyrim:Lockpicking" with the install's
// GMSTs; turn speeds are OpenSky's. See docs/engine/locks.md.

import Foundation
import OpenSkyInventoryInterface

/// The numbers one session plays with, after skill and perks.
nonisolated public struct LockpickingParameters: Equatable, Sendable {
    public let difficulty: LockDifficulty
    /// Full sweet-spot width in degrees.
    public let sweetSpotWidth: Float
    /// Width of each partial zone beside the sweet spot, in degrees.
    public let partialWidth: Float
    /// Seconds of straining that break one pick.
    public let breakSeconds: Float
    public let unbreakable: Bool
    /// `Set Lockpick Starting Arc`: a fresh pick starts within this many degrees of the
    /// sweet spot. Zero starts it upright.
    public let startingArc: Float
    public let halfArc: Float

    public init(
        difficulty: LockDifficulty,
        sweetSpotWidth: Float,
        partialWidth: Float,
        breakSeconds: Float,
        unbreakable: Bool = false,
        startingArc: Float = 0,
        halfArc: Float = LockpickingSettings.documentedDefaults.halfArc
    ) {
        self.difficulty = difficulty
        self.sweetSpotWidth = sweetSpotWidth
        self.partialWidth = partialWidth
        self.breakSeconds = breakSeconds
        self.unbreakable = unbreakable
        self.startingArc = startingArc
        self.halfArc = halfArc
    }

    /// UESP: sweet spot `base * (0.82 + 0.6 * Level / 100) * perk`, partial zone
    /// `base * (0.775 + 1.5 * Level / 100)`, break time `base * (1 + 0.5 * Level / 100)`.
    /// `sweetSpotPerk` is the `Mod Lockpick Sweet Spot` result for the unmodified width.
    public static func make(
        difficulty: LockDifficulty,
        skill: Float,
        settings: LockpickingSettings,
        perks: LockpickingPerkValues = .none
    ) -> LockpickingParameters {
        let level = min(max(skill, 0), 100)
        let sweet = (settings.sweetSpot[difficulty] ?? 0)
            * (settings.sweetSpotSkillBase + settings.sweetSpotSkillMult * level)
        let partial = (settings.partialPick[difficulty] ?? 0)
            * (settings.partialSkillBase + settings.partialSkillMult * level)
        let breakTime = (settings.breakSeconds[difficulty] ?? 1)
            * (1 + settings.breakSkillMult * level)
        return LockpickingParameters(
            difficulty: difficulty,
            sweetSpotWidth: sweet * perks.sweetSpotFactor,
            partialWidth: partial,
            breakSeconds: breakTime,
            unbreakable: perks.unbreakable,
            startingArc: perks.startingArc,
            halfArc: settings.halfArc
        )
    }
}

/// What the owner's perks answered at the lockpicking entry points.
nonisolated public struct LockpickingPerkValues: Equatable, Sendable {
    public static let none = LockpickingPerkValues()

    /// `Mod Lockpick Sweet Spot` applied to 1.
    public var sweetSpotFactor: Float = 1
    /// `Set Lockpick Starting Arc`, in degrees. Locksmith sets 45.
    public var startingArc: Float = 0
    /// `Make Lockpicks Unbreakable` set above zero. Unbreakable sets 1.
    public var unbreakable = false
    /// `Mod Lockpicking Key Reward Chance`, in percent. Wax Key sets 100.
    public var keyRewardChance: Float = 0

    public init(
        sweetSpotFactor: Float = 1,
        startingArc: Float = 0,
        unbreakable: Bool = false,
        keyRewardChance: Float = 0
    ) {
        self.sweetSpotFactor = sweetSpotFactor
        self.startingArc = startingArc
        self.unbreakable = unbreakable
        self.keyRewardChance = keyRewardChance
    }
}

/// One frame of player input.
nonisolated public struct LockpickingInput: Equatable, Sendable {
    /// Degrees to move the pick, positive to the right. Ignored while turning.
    public var pickDelta: Float
    /// True while the player turns the lock.
    public var turning: Bool

    public static let idle = LockpickingInput(pickDelta: 0, turning: false)

    public init(pickDelta: Float, turning: Bool) {
        self.pickDelta = pickDelta
        self.turning = turning
    }
}

nonisolated public enum LockpickingEvent: Equatable, Sendable {
    case pickBroke
    case opened
    case outOfPicks
    case cancelled
}

/// One lockpicking session. Deterministic: the sweet spot is an input.
nonisolated public struct LockpickingSession: Equatable, Sendable {
    /// Lock turn per second while turning, as a fraction of a full turn. OpenSky's value.
    public static let turnRate: Float = 1.5
    /// Lock turn per second back toward rest once released. OpenSky's value.
    public static let returnRate: Float = 3

    public let parameters: LockpickingParameters
    /// Centre of the sweet spot, in degrees from upright.
    public let sweetSpotCenter: Float
    public private(set) var pickAngle: Float
    /// 0 at rest, 1 fully turned (open).
    public private(set) var lockRotation: Float = 0
    /// 1 for a fresh pick, 0 when it breaks.
    public private(set) var pickHealth: Float
    public private(set) var picksRemaining: Int32
    public private(set) var picksBroken = 0
    public private(set) var isFinished = false
    /// Where a fresh pick goes in: upright, or `startingOffset` from the sweet spot.
    private let freshPickAngle: Float

    /// - Parameters:
    ///   - startingOffset: in -1...1, scales `startingArc` for where a fresh pick starts.
    public init(
        parameters: LockpickingParameters,
        sweetSpotCenter: Float,
        picks: Int32,
        pickHealth: Float = 1,
        startingOffset: Float = 0
    ) {
        self.parameters = parameters
        let limit = parameters.halfArc
        self.sweetSpotCenter = min(max(sweetSpotCenter, -limit), limit)
        let fresh = parameters.startingArc > 0
            ? self.sweetSpotCenter + parameters.startingArc / 2 * min(max(startingOffset, -1), 1)
            : 0
        freshPickAngle = min(max(fresh, -limit), limit)
        pickAngle = freshPickAngle
        self.pickHealth = min(max(pickHealth, 0), 1)
        picksRemaining = max(picks, 0)
        isFinished = picks <= 0
    }

    /// How far the lock may turn with the pick at `angle`: 1 in the sweet spot,
    /// falling to 0 across a partial zone, 0 beyond it.
    public func allowedRotation(at angle: Float) -> Float {
        let distance = abs(angle - sweetSpotCenter)
        let halfSweet = parameters.sweetSpotWidth / 2
        if distance <= halfSweet {
            return 1
        }
        guard parameters.partialWidth > 0 else { return 0 }
        return max(0, 1 - (distance - halfSweet) / parameters.partialWidth)
    }

    public var allowedRotation: Float {
        allowedRotation(at: pickAngle)
    }

    /// True when turning now strains the pick: the lock has stopped short of open.
    public func isStraining(_ input: LockpickingInput) -> Bool {
        input.turning && allowedRotation < 1 && lockRotation >= allowedRotation
    }

    /// Advances `seconds` of play. Returns what happened, in order.
    public mutating func step(_ seconds: Float, input: LockpickingInput) -> [LockpickingEvent] {
        guard !isFinished, seconds > 0, seconds.isFinite else { return [] }
        guard input.turning else {
            lockRotation = max(0, lockRotation - Self.returnRate * seconds)
            let limit = parameters.halfArc
            pickAngle = min(max(pickAngle + input.pickDelta, -limit), limit)
            return []
        }
        let allowed = allowedRotation
        lockRotation = min(allowed, lockRotation + Self.turnRate * seconds)
        if allowed >= 1, lockRotation >= 1 {
            isFinished = true
            return [.opened]
        }
        guard lockRotation >= allowed, !parameters.unbreakable else { return [] }
        pickHealth -= seconds / max(parameters.breakSeconds, .ulpOfOne)
        guard pickHealth <= 0 else { return [] }
        return breakPick()
    }

    /// Ends the session without opening the lock.
    public mutating func cancel() -> [LockpickingEvent] {
        guard !isFinished else { return [] }
        isFinished = true
        return [.cancelled]
    }

    private mutating func breakPick() -> [LockpickingEvent] {
        picksBroken += 1
        picksRemaining -= 1
        pickHealth = 1
        lockRotation = 0
        pickAngle = freshPickAngle
        guard picksRemaining > 0 else {
            isFinished = true
            return [.pickBroke, .outOfPicks]
        }
        return [.pickBroke]
    }
}

// The settings of the out-of-range and out-of-position moves of a styled melee NPC, and
// the strafe of a styled archer. See docs/engine/combat-movement.md.

import Foundation

/// What a styled melee NPC does when its advance fails or it stands out of its place.
nonisolated public struct CombatMovementSettings: Equatable, Sendable {
    /// `lerp(circle, 0.25, 0.75)`: the distant circle roll.
    public var distantCircleChance: Float = 0.35
    /// The distant circle angle, drawn from `min` to `max`, in degrees.
    public var distantCircleAngle = CombatSettingRange(30, 42)
    /// The distant circle angle against the player.
    public var playerAngleMult: Float = 0.75
    /// The least distant circle arc, in actor radii.
    public var minimumArcRadii: Float = 3
    /// The surround ring, beyond `reach + inner advance radius`.
    public var surroundRing = CombatSettingRange(128, 384)
    /// The advance fails once its path has failed for longer than this.
    public var advanceFailSeconds: Float = 1
    /// The wait after a pass that started no move.
    public var waitSeconds: Float = 0.25
    /// A distant circle starts only while the NPC faces its target within this angle.
    public var startFacingDegrees: Float = 30

    /// The settings of a style with this `CSCR` circle value.
    public init(circle: Float) {
        distantCircleChance = CombatSettingRange(0.25, 0.75).lerp(circle)
        distantCircleAngle = CombatSettingRange(30, CombatSettingRange(30, 90).lerp(circle))
    }
}

/// The strafe of a styled archer: a pass every `passSeconds` rolls `chance`.
nonisolated public struct CombatStrafeSettings: Equatable, Sendable {
    /// `lerp(strafe, 0, 0.75)`, with the style's `CSLR` value.
    public var chance: Float
    /// The strafe distance, drawn from `min` to `max`, and at least `minimumRadii` radii.
    public var distance = CombatSettingRange(96, 256)
    public var minimumRadii: Float = 3
    public var passSeconds: Float = 0.25
    /// A strafe starts only while the NPC faces its target within this angle.
    public var startFacingDegrees: Float = 30

    public init(strafe: Float) {
        chance = CombatSettingRange(0, 0.75).lerp(strafe)
    }
}

/// The flanking loop of a style with `DATA` flag 0x02: a stalk, then a flank choice.
nonisolated public struct CombatFlankSettings: Equatable, Sendable {
    /// `lerp(stalk time, 0.01, 10)`, and the most a stalk lasts.
    public var stalkSeconds: Float
    public var stalkLimitSeconds: Float = 10
    /// The stalk keeps the NPC between its reach and `reach + stalkBand`. It starts only
    /// below the maximum range plus `stalkBand`.
    public var stalkBand: Float = 256
    /// `lerp(flank distance, 0, 1024)`.
    public var flankDistance: Float
    /// Within `reach + anyAngleDistance` a flank goal may lie at any angle; further out the
    /// angle widens from `angle.min` to `angle.max` degrees at `fullAngleDistance`.
    public var anyAngleDistance: Float = 384
    public var fullAngleDistance: Float = 1024
    public var angle = CombatSettingRange(10, 30)
    public var watchSeconds: Float = 1

    public init(stalkTime: Float, flankDistance: Float) {
        stalkSeconds = CombatSettingRange(0.01, 10).lerp(stalkTime)
        self.flankDistance = CombatSettingRange(0, 1024).lerp(flankDistance)
    }

    /// The most a flank goal may lie off the NPC's bearing, in radians, at `distance`
    /// beyond its reach. Nil means any angle.
    public func angleLimit(beyondReach distance: Float) -> Float? {
        guard distance > anyAngleDistance else { return nil }
        let span = max(fullAngleDistance - anyAngleDistance, 1)
        let share = min((distance - anyAngleDistance) / span, 1)
        return angle.lerp(share) * .pi / 180
    }
}

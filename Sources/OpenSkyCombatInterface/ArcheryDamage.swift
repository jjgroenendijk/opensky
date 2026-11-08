import Foundation

/// One resolved shot's damage accounting, kept whole so a readout can explain
/// a number rather than just show it.
nonisolated public struct ArcheryDamageResult: Equatable, Sendable {
    /// WEAP base damage.
    public let bowDamage: Float
    /// AMMO base damage.
    public let arrowDamage: Float
    /// The draw-time fraction, `0...1`.
    public let drawFraction: Float
    /// What actually comes off health.
    public let applied: Float

    /// The two base damages before the draw term, which is what the weapon
    /// sheet in vanilla shows.
    public var combinedBase: Float {
        bowDamage + arrowDamage
    }

    public init(
        bowDamage: Float,
        arrowDamage: Float,
        drawFraction: Float,
        applied: Float
    ) {
        self.bowDamage = bowDamage
        self.arrowDamage = arrowDamage
        self.drawFraction = drawFraction
        self.applied = applied
    }
}

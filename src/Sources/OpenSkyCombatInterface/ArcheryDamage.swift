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

nonisolated extension ArcheryDamageResult {
    /// The lowest draw power, `fArrowMinPower`.
    static let minimumPower: Float = 0.35
    /// `fArrowWeakGravity`: the gravity a shot at no power falls with.
    static let weakGravity: Float = 1.75

    /// The share of the `PROJ` speed a shot leaves at: 0.2 at the lowest power, 1 at full.
    var launchSpeedShare: Float {
        let power = min(max(drawFraction, Self.minimumPower), 1)
        return 0.2 + 0.8 * (power - Self.minimumPower) / (1 - Self.minimumPower)
    }

    /// The gravity a shot falls with: the record's own at full power, mixed towards
    /// `weakGravity` by the power.
    func gravity(recordGravity: Float) -> Float {
        let power = min(max(drawFraction, 0), 1)
        return Self.weakGravity - (Self.weakGravity - recordGravity) * power
    }
}

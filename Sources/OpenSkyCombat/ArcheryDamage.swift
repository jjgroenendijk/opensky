// How much health a landed arrow takes off. Base damage is the WEAP's plus the
// AMMO's, and a partial draw scales it by UESP's approximate draw formula.
// Documented in docs/engine/archery.md.

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
}

nonisolated public enum ArcheryDamage: Sendable {
    /// The Archery skill assumed for a character with no skill table: 15, the starting
    /// value for a race with no Archery bonus (UESP "Skyrim:Archery"). Same reasoning as
    /// `MeleeDamage.defaultBlockSkill`.
    public static let defaultArcherySkill: Float = 15

    /// The lowest fraction a released shot can deal, from the page's first
    /// branch.
    public static let minimumDrawFraction: Float = 0.35

    /// Frames per second the draw-time formula is written in. The page states
    /// it in frames and says "to calculate using seconds, replace t by 60t".
    public static let drawFormulaFrameRate: Float = 60

    /// What one landed arrow takes off the target's health. `drawFraction` is 0...1 (1 is
    /// a full draw). `bonusMultiplier` folds perks, enchantments and potions; 1 for none.
    /// `CombatFortifyBonus.archery` supplies the enchantment and potion part.
    public static func resolve(
        bowDamage: Float,
        arrowDamage: Float,
        drawFraction: Float = 1,
        skill: Float = defaultArcherySkill,
        bonusMultiplier: Float = 1
    ) -> ArcheryDamageResult {
        let bow = clamp(bowDamage)
        let arrow = clamp(arrowDamage)
        let draw = min(max(clamp(drawFraction), 0), 1)
        let skillTerm = 1 + clamp(skill) / 200
        let bonus = bonusMultiplier.isFinite ? max(0, bonusMultiplier) : 1
        let applied = (bow + arrow) * draw * skillTerm * bonus
        return ArcheryDamageResult(
            bowDamage: bow,
            arrowDamage: arrow,
            drawFraction: draw,
            applied: applied.isFinite ? max(0, applied) : 0
        )
    }

    /// The draw fraction after `heldSeconds`, from UESP's three-branch formula. `speed` is
    /// WEAP DNAM speed times any multiplier; a non-positive or non-finite one becomes 1.
    public static func drawFraction(heldSeconds: Float, speed: Float) -> Float {
        let scale = speed.isFinite && speed > 0 ? speed : 1
        let frames = heldSeconds.isFinite ? max(0, heldSeconds) * drawFormulaFrameRate : 0
        let lower = 50 + 12 / scale
        let upper = 50 + 52 / scale
        if frames < lower {
            return minimumDrawFraction
        }
        if frames > upper {
            return 1
        }
        let percent = (100 / 80) * (28 + scale * (frames - 50))
        return min(max(percent / 100, minimumDrawFraction), 1)
    }

    private static func clamp(_ value: Float) -> Float {
        value.isFinite ? max(0, value) : 0
    }
}

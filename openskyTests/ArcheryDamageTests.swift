// The bow-plus-arrow damage combination and the draw-time curve (issue #196,
// roadmap item 15.5, scope point 4).
//
// The issue's acceptance says the tests verify "the damage combination", so
// both formulas are written out longhand in the expectations rather than being
// recomputed from the helper under test. Both are UESP's:
//
//   "Skyrim:Archery", Detailed Bow Comparison — (bow damage + arrow damage)
//   "Skyrim:Weapons", Overview — * (1 + skill/200) * (1 + perk effects) * ...
//   "Skyrim:Archery", Draw Time and Damage Dealt — the three-branch curve.

@testable import opensky
import Testing

struct ArcheryDamageTests {
    @Test func aFullDrawAddsTheBowAndTheArrow() {
        // Hunting bow 7 plus iron arrow 8 = 15, at the default skill 15:
        // 15 * (1 + 15/200) = 15 * 1.075 = 16.125.
        let result = ArcheryDamage.resolve(bowDamage: 7, arrowDamage: 8)

        #expect(result.bowDamage == 7)
        #expect(result.arrowDamage == 8)
        #expect(result.combinedBase == 15)
        #expect(result.drawFraction == 1)
        #expect(abs(result.applied - 16.125) < 0.0001)
    }

    @Test func theSkillTermIsOneHalfPercentPerPoint() {
        let novice = ArcheryDamage.resolve(bowDamage: 10, arrowDamage: 10, skill: 0)
        let master = ArcheryDamage.resolve(bowDamage: 10, arrowDamage: 10, skill: 100)

        #expect(abs(novice.applied - 20) < 0.0001)
        // 20 * (1 + 100/200) = 30.
        #expect(abs(master.applied - 30) < 0.0001)
    }

    @Test func aPartialDrawScalesTheWholeCombination() {
        let result = ArcheryDamage.resolve(
            bowDamage: 7, arrowDamage: 8, drawFraction: 0.35, skill: 0
        )

        #expect(abs(result.applied - 15 * 0.35) < 0.0001)
    }

    @Test func thePerkAndEnchantmentTermIsOneUntilM18SuppliesIt() {
        let plain = ArcheryDamage.resolve(bowDamage: 10, arrowDamage: 0, skill: 0)
        let perked = ArcheryDamage.resolve(
            bowDamage: 10, arrowDamage: 0, skill: 0, bonusMultiplier: 1.2
        )

        #expect(abs(plain.applied - 10) < 0.0001)
        #expect(abs(perked.applied - 12) < 0.0001)
    }

    // MARK: - The draw curve

    /// UESP: "35% if t < 50 + 12 / (Speed * WeaponSpeedMult)". At speed 1 that
    /// threshold is 62 frames, so anything under about 1.033 s is a snap shot.
    @Test func aShortHoldDealsTheMinimumThirtyFivePercent() {
        #expect(ArcheryDamage.drawFraction(heldSeconds: 0, speed: 1) == 0.35)
        #expect(ArcheryDamage.drawFraction(heldSeconds: 1, speed: 1) == 0.35)
    }

    /// UESP: "100% if t > 50 + 52 / (Speed * WeaponSpeedMult)". At speed 1 that
    /// is 102 frames, so anything past 1.7 s is a full draw.
    @Test func aLongHoldDealsFullDamage() {
        #expect(ArcheryDamage.drawFraction(heldSeconds: 2, speed: 1) == 1)
        #expect(ArcheryDamage.drawFraction(heldSeconds: 10, speed: 1) == 1)
    }

    /// The middle branch, written out: (100/80) * (28 + speed * (t - 50)).
    /// At speed 1 and 80 frames (1.3333 s) that is 1.25 * (28 + 30) = 72.5%.
    @Test func theMiddleBranchIsUESPsFormula() {
        let fraction = ArcheryDamage.drawFraction(heldSeconds: 80.0 / 60, speed: 1)

        #expect(abs(fraction - 0.725) < 0.001)
    }

    /// A faster bow reaches full draw sooner, which is what makes the
    /// `Speed * WeaponSpeedMult` denominator do anything at all.
    @Test func aFasterBowReachesFullDrawSooner() {
        // 66 frames: past the 63-frame full-draw threshold at speed 4, still
        // short of the 74-frame minimum threshold at speed 0.5.
        let slow = ArcheryDamage.drawFraction(heldSeconds: 66.0 / 60, speed: 0.5)
        let fast = ArcheryDamage.drawFraction(heldSeconds: 66.0 / 60, speed: 4)

        #expect(fast > slow)
        #expect(fast == 1)
    }

    @Test func aNonPositiveSpeedFallsBackToOne() {
        let zero = ArcheryDamage.drawFraction(heldSeconds: 2, speed: 0)
        let one = ArcheryDamage.drawFraction(heldSeconds: 2, speed: 1)

        #expect(zero == one)
    }

    @Test func nonFiniteInputsProduceNoDamageRatherThanNaN() {
        let result = ArcheryDamage.resolve(
            bowDamage: .nan, arrowDamage: .infinity, drawFraction: .nan, skill: .nan
        )

        #expect(result.bowDamage == 0)
        #expect(result.arrowDamage == 0)
        #expect(result.applied == 0)
        #expect(ArcheryDamage.drawFraction(heldSeconds: .nan, speed: .nan) == 0.35)
    }

    @Test func theDrawFractionIsClampedIntoZeroToOne() {
        let over = ArcheryDamage.resolve(bowDamage: 10, arrowDamage: 0, drawFraction: 5, skill: 0)
        let under = ArcheryDamage.resolve(bowDamage: 10, arrowDamage: 0, drawFraction: -5, skill: 0)

        #expect(abs(over.applied - 10) < 0.0001)
        #expect(under.applied == 0)
    }
}

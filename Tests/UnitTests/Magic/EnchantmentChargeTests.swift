// The charge arithmetic on its own (issue #472, roadmap item 19.9): uses,
// spending, the stranded remainder, and the unmetered case.
//
// Pure values, no store and no records, which is what makes `floor(charge / cost)`
// a plain assertion rather than something only a running session can show. The
// same ratio is pinned against UESP's published rows in
// `EnchantmentRuntimeRealDataTests`.

import Foundation
@testable import opensky
import Testing

struct EnchantmentChargeTests {
    /// UESP's first published row: 1000 charge at 18 per use is 55 uses, not 55.5.
    @Test func usesFloorTheRatio() {
        let charge = EnchantmentCharge(capacity: 1000, costPerUse: 18)
        #expect(charge.usesRemaining == 55)
        #expect(charge.isMetered)
        #expect(charge.canFire)
        #expect(charge.fraction == 1)
    }

    @Test func spendingTakesExactlyOneUse() throws {
        let charge = EnchantmentCharge(capacity: 90, costPerUse: 18)
        let after = try #require(charge.spending())
        #expect(after.remaining == 72)
        #expect(after.capacity == 90)
        #expect(after.usesRemaining == 4)
    }

    /// Five uses, then nothing. The sixth hit cannot pay and reports so rather
    /// than firing on a negative charge.
    @Test func aWeaponRunsOutAfterItsLastUse() {
        var charge: EnchantmentCharge? = EnchantmentCharge(capacity: 90, costPerUse: 18)
        var fired = 0
        while let next = charge?.spending() {
            charge = next
            fired += 1
        }
        #expect(fired == 5)
        #expect(charge?.remaining == 0)
        #expect(charge?.canFire == false)
        #expect(charge?.usesRemaining == 0)
    }

    /// A partial use is stranded, not spent: a weapon holding less than one whole
    /// use cannot fire at all, which is why `usesRemaining` floors.
    @Test func aPartialUseIsStrandedRatherThanSpent() {
        let charge = EnchantmentCharge(capacity: 100, remaining: 10, costPerUse: 18)
        #expect(charge.usesRemaining == 0)
        #expect(!charge.canFire)
        #expect(charge.spending() == nil)
        #expect(charge.remaining == 10)
    }

    /// An enchantment that charges nothing fires forever and never writes a
    /// changed charge, which is what keeps a cost-free weapon from making its
    /// owner dirty on every swing.
    @Test func anUnmeteredEnchantmentNeverRunsDown() throws {
        let charge = EnchantmentCharge(capacity: 0, costPerUse: 0)
        #expect(!charge.isMetered)
        #expect(charge.canFire)
        #expect(charge.usesRemaining == Int.max)
        #expect(try #require(charge.spending()) == charge)
        #expect(charge.describedLine == "no charge")
    }

    /// Garbage from a mod-authored record normalizes rather than propagating: a
    /// negative or non-finite charge reads as zero, and remaining never exceeds
    /// the capacity.
    @Test func nonsensicalNumbersNormalize() {
        #expect(EnchantmentCharge(capacity: -50, costPerUse: 10).capacity == 0)
        #expect(EnchantmentCharge(capacity: .nan, costPerUse: 10).capacity == 0)
        #expect(EnchantmentCharge(capacity: 100, remaining: 500, costPerUse: 10).remaining == 100)
        #expect(EnchantmentCharge(capacity: 100, remaining: -5, costPerUse: 10).remaining == 0)
        #expect(EnchantmentCharge(capacity: 100, costPerUse: .infinity).costPerUse == 0)
    }

    @Test func restoringCapsAtTheCapacity() {
        let empty = EnchantmentCharge(capacity: 90, remaining: 0, costPerUse: 18)
        #expect(empty.restoring(to: 200).remaining == 90)
        #expect(empty.restoring(to: 36).usesRemaining == 2)
    }

    /// The readout line names both numbers and the uses, so a panel prints a
    /// charge without knowing the model.
    @Test func theReadoutLineNamesChargeAndUses() {
        let charge = EnchantmentCharge(capacity: 90, remaining: 72, costPerUse: 18)
        #expect(charge.describedLine == "72/90 charge, 4 use(s) left")
    }
}

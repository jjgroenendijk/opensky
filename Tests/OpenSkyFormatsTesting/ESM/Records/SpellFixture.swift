// Record builder shared by the parser tests and the runtime tests that feed
// the same records to a store. Every byte is built in code.

import Foundation

public enum SpellFixture: Sendable {
    /// The 36-byte SPIT struct: base cost, flags, type, charge time, casting
    /// type, delivery, cast duration, range, half-cost PERK.
    public static func spit(
        baseCost: UInt32 = 0,
        flags: UInt32 = 0,
        type: UInt32 = 0,
        chargeTime: Float = 0.5,
        castingType: UInt32 = 1,
        delivery: UInt32 = 2,
        castDuration: Float = 0,
        range: Float = 0,
        halfCostPerk: UInt32 = 0
    ) -> Data {
        MagicEffectFixture.words([
            baseCost,
            flags,
            type,
            chargeTime.bitPattern,
            castingType,
            delivery,
            castDuration.bitPattern,
            range.bitPattern,
            halfCostPerk
        ])
    }
}

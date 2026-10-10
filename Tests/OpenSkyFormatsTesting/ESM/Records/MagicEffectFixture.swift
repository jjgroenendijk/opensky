// Record builder shared by the parser tests and the runtime tests that feed
// the same records to a store. Every byte is built in code.

import Foundation
@testable import OpenSkyFormatsESM

public enum MagicEffectFixture: Sendable {
    public static func data(
        archetype: UInt32 = 0,
        castingType: UInt32 = 1,
        delivery: UInt32 = 2,
        baseCost: Float = 12.5
    ) -> Data {
        words([
            MagicEffectFlags.hostile.rawValue, baseCost.bitPattern, 0x100, 20, 44, 0,
            0x101, Float(0.5).bitPattern, 0x102, 0x103, 25, 10,
            Float(0.75).bitPattern, Float(1.25).bitPattern, Float(2).bitPattern,
            Float(0.4).bitPattern, archetype, 24, 0x200, 0x201, castingType, delivery, 25,
            0x202, 0x203, 0x204, Float(1.5).bitPattern, 0x205, Float(2.5).bitPattern,
            0x206, 0x207, 0x208, 0x209, 0x20A, 0x20B, 1,
            Float(50).bitPattern, Float(1).bitPattern
        ])
    }

    public static func record(type: String, formID: UInt32 = 0, fields: Data) throws -> ESMRecord {
        try ESMFixture.parsedRecord(type: type, fields: fields, formID: formID)
    }

    public static func words(_ values: [UInt32]) -> Data {
        ESMFixture.words(values)
    }
}

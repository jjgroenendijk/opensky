// Synthetic SPEL, SCRL and MGEF fixtures shared by the spell store and record-dump suites.
// Every byte is authored here; nothing comes from the game install.

import Foundation
@testable import OpenSkyFormatsESM
import Testing

public enum SpellStoreFixture: Sendable {
    public struct EffectSpec: Sendable {
        public let effect: UInt32
        public let magnitude: Float
        public let duration: UInt32
        public let area: UInt32

        public init(_ effect: UInt32, magnitude: Float, duration: UInt32 = 0, area: UInt32 = 0) {
            self.effect = effect
            self.magnitude = magnitude
            self.duration = duration
            self.area = area
        }
    }

    /// Two MGEF definitions with known base costs, so every total in the
    /// suites is hand-computable: 0x50 costs 10 per unit, 0x51 costs 2.5.
    public static var effectRecords: [Data] {
        [
            magicEffect(formID: 0x50, editorID: "FireDamage", name: "Fire Damage", cost: 10),
            magicEffect(formID: 0x51, editorID: "FireCloak", name: "Fire Cloak", cost: 2.5)
        ]
    }

    public static func spellFields(
        editorID: String,
        name: String,
        spit: Data,
        effects: [EffectSpec]
    ) -> Data {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring(editorID))
        fields += ESMFixture.field("FULL", ESMFixture.zstring(name))
        fields += ESMFixture.field("SPIT", spit)
        for effect in effects {
            fields += InventoryFixture.effectFields(
                effect: effect.effect,
                magnitude: effect.magnitude,
                area: effect.area,
                duration: effect.duration
            )
        }
        return fields
    }

    public static func magicEffect(
        formID: UInt32,
        editorID: String,
        name: String,
        cost: Float
    ) -> Data {
        ESMFixture.record(
            "MGEF",
            formID: formID,
            data: ESMFixture.field("EDID", ESMFixture.zstring(editorID))
                + ESMFixture.field("FULL", ESMFixture.zstring(name))
                + ESMFixture.field("DATA", MagicEffectFixture.data(baseCost: cost))
        )
    }

    /// CRDT: uint16 damage, 2 unused, float multiplier, uint8 on-death,
    /// 3 unused, FormID SPEL effect.
    public static func criticalData(effect: UInt32) -> Data {
        var data = Data()
        data.appendUInt16(5)
        data.appendUInt16(0)
        data.appendUInt32(Float(1).bitPattern)
        data.append(contentsOf: [0, 0, 0, 0])
        data.appendUInt32(effect)
        return data
    }

    public static func plugin(masters: [String] = [], records: [Data]) throws -> ESMFile {
        try ESMFixture.plugin(masters: masters, records: records)
    }

    public static func firstRecord(type: String, in file: ESMFile) throws -> ESMRecord {
        try ESMFixture.firstRecord(type: type, in: file)
    }
}

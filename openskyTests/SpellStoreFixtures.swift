// Synthetic SPEL, SCRL and MGEF fixtures shared by the SpellStore suites.
// Every byte is authored here; nothing comes from the game install.

import Foundation
@testable import opensky
import Testing

enum SpellStoreFixture {
    struct EffectSpec {
        let effect: UInt32
        let magnitude: Float
        let duration: UInt32

        init(_ effect: UInt32, magnitude: Float, duration: UInt32 = 0) {
            self.effect = effect
            self.magnitude = magnitude
            self.duration = duration
        }
    }

    /// Two MGEF definitions with known base costs, so every total in the
    /// suites is hand-computable: 0x50 costs 10 per unit, 0x51 costs 2.5.
    static var effectRecords: [Data] {
        [
            magicEffect(formID: 0x50, editorID: "FireDamage", name: "Fire Damage", cost: 10),
            magicEffect(formID: 0x51, editorID: "FireCloak", name: "Fire Cloak", cost: 2.5)
        ]
    }

    static func store(spellFields: Data) throws -> SpellStore {
        let file = try plugin(
            records: effectRecords + [ESMFixture.record("SPEL", formID: 0x42, data: spellFields)]
        )
        return SpellStore(plugins: [("Base.esm", file)])
    }

    static func spellFields(
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
                area: 0,
                duration: effect.duration
            )
        }
        return fields
    }

    static func magicEffect(
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
    static func criticalData(effect: UInt32) -> Data {
        var data = Data()
        data.appendUInt16(5)
        data.appendUInt16(0)
        data.appendUInt32(Float(1).bitPattern)
        data.append(contentsOf: [0, 0, 0, 0])
        data.appendUInt32(effect)
        return data
    }

    static func plugin(masters: [String] = [], records: [Data]) throws -> ESMFile {
        let grouped = Dictionary(grouping: records) { record in
            String(bytes: record.prefix(4), encoding: .ascii) ?? "SPEL"
        }
        var data = ESMFixture.tes4(masters: masters)
        for (type, groupedRecords) in grouped.sorted(by: { $0.key < $1.key }) {
            data += ESMFixture.topGroup(type, contents: groupedRecords.reduce(Data(), +))
        }
        return try ESMFile(data: data)
    }

    static func firstRecord(type: String, in file: ESMFile) throws -> ESMRecord {
        let group = try #require(file.topGroups.first { $0.recordType?.description == type })
        let child = try #require(try group.children().first)
        guard case let .record(record) = child else {
            throw ESMError.malformed("fixture child is not a record")
        }
        return record
    }
}

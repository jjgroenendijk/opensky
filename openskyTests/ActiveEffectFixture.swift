// Synthetic MGEF, ALCH and INGR fixtures for the active-effect suites (issue
// #469, roadmap item 19.6). Every byte is authored here; nothing comes from the
// game install (AGENTS.md "Legal & IP boundary").
//
// The DATA layout is UESP "Skyrim Mod:Mod File Format/MGEF" — 152 bytes, with
// the fields these suites care about at 0x00 flags, 0x08 associated item, 0x3C
// second actor-value weight, 0x40 archetype, 0x44 primary actor value and 0x58
// second actor value.

import Foundation
@testable import opensky
import Testing

@MainActor
enum ActiveEffectFixture {
    static let pluginName = "Base.esm"

    /// Restore Health: value modifier, health, not detrimental, no Recover.
    static let restoreHealth: UInt32 = 0x10
    /// Damage Health: value modifier, health, detrimental.
    static let damageHealth: UInt32 = 0x11
    /// Fortify Resist Fire: value modifier on a non-primary value with
    /// Recover set, which is the archetype's held-modifier behaviour.
    static let fortifyResistFire: UInt32 = 0x12
    /// A dual value modifier over resist fire and resist frost.
    static let dualResist: UInt32 = 0x13
    /// An archetype this milestone does not implement.
    static let paralyze: UInt32 = 0x14
    /// A peak value modifier sharing keyword 0x900.
    static let peakResist: UInt32 = 0x15

    static let stackKeyword: UInt32 = 0x900

    /// One MGEF DATA block. Every field this milestone reads is a parameter;
    /// the rest are zero, which is a valid record and keeps the fixture honest
    /// about what the planner actually consumes.
    static func data(
        flags: MagicEffectFlags = [],
        associatedItem: UInt32 = 0,
        secondValueWeight: Float = 0,
        archetype: UInt32 = 0,
        primaryValue: Int32 = 24,
        secondValue: Int32 = -1
    ) -> Data {
        var words = [UInt32](repeating: 0, count: 38)
        words[0] = flags.rawValue
        words[2] = associatedItem
        words[15] = secondValueWeight.bitPattern
        words[16] = archetype
        words[17] = UInt32(bitPattern: primaryValue)
        words[22] = UInt32(bitPattern: secondValue)
        var data = Data()
        for word in words {
            data.appendUInt32(word)
        }
        return data
    }

    static func magicEffect(
        formID: UInt32,
        editorID: String,
        name: String,
        data: Data
    ) -> Data {
        ESMFixture.record(
            "MGEF",
            formID: formID,
            data: ESMFixture.field("EDID", ESMFixture.zstring(editorID))
                + ESMFixture.field("FULL", ESMFixture.zstring(name))
                + ESMFixture.field("DATA", data)
        )
    }

    /// The six effects every suite shares.
    static var effectRecords: [Data] {
        [
            magicEffect(
                formID: restoreHealth, editorID: "RestoreHealth", name: "Restore Health",
                data: data(archetype: 0, primaryValue: 24)
            ),
            magicEffect(
                formID: damageHealth, editorID: "DamageHealth", name: "Damage Health",
                data: data(flags: [.detrimental], archetype: 0, primaryValue: 24)
            ),
            magicEffect(
                formID: fortifyResistFire, editorID: "FortifyResistFire",
                name: "Fortify Resist Fire",
                data: data(
                    flags: [.recover], archetype: 0,
                    primaryValue: ActorValueIndex.resistFire
                )
            ),
            magicEffect(
                formID: dualResist, editorID: "DualResist", name: "Dual Resist",
                data: data(
                    flags: [.recover], secondValueWeight: 0.5, archetype: 5,
                    primaryValue: ActorValueIndex.resistFire,
                    secondValue: ActorValueIndex.resistFrost
                )
            ),
            magicEffect(
                formID: paralyze, editorID: "Paralyze", name: "Paralyze",
                data: data(flags: [.recover], archetype: 21, primaryValue: 53)
            ),
            magicEffect(
                formID: peakResist, editorID: "PeakResist", name: "Peak Resist",
                data: data(
                    flags: [.recover], associatedItem: stackKeyword, archetype: 34,
                    primaryValue: ActorValueIndex.resistFire
                )
            )
        ]
    }

    struct EffectSpec {
        let effect: UInt32
        let magnitude: Float
        let duration: UInt32
        let conditions: Data

        init(_ effect: UInt32, magnitude: Float, duration: UInt32 = 0, conditions: Data = Data()) {
            self.effect = effect
            self.magnitude = magnitude
            self.duration = duration
            self.conditions = conditions
        }
    }

    static func ingestible(
        formID: UInt32,
        editorID: String,
        effects: [EffectSpec]
    ) -> Data {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring(editorID))
        fields += ESMFixture.field("DATA", floatData(0.5))
        fields += ESMFixture.field("ENIT", enit)
        for effect in effects {
            fields += effectFields(effect)
        }
        return ESMFixture.record("ALCH", formID: formID, data: fields)
    }

    static func ingredient(
        formID: UInt32,
        editorID: String,
        effects: [EffectSpec]
    ) -> Data {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring(editorID))
        fields += ESMFixture.field("DATA", InventoryFixture.valueWeightData(value: 1, weight: 0.1))
        var ingredientENIT = Data()
        ingredientENIT.appendUInt32(0)
        ingredientENIT.appendUInt32(0)
        fields += ESMFixture.field("ENIT", ingredientENIT)
        for effect in effects {
            fields += effectFields(effect)
        }
        return ESMFixture.record("INGR", formID: formID, data: fields)
    }

    static func plugin(records: [Data]) throws -> ESMFile {
        let grouped = Dictionary(grouping: records) { record in
            String(bytes: record.prefix(4), encoding: .ascii) ?? "MGEF"
        }
        var data = ESMFixture.tes4()
        for (type, groupedRecords) in grouped.sorted(by: { $0.key < $1.key }) {
            data += ESMFixture.topGroup(type, contents: groupedRecords.reduce(Data(), +))
        }
        return try ESMFile(data: data)
    }

    // MARK: - Private

    private static func effectFields(_ effect: EffectSpec) -> Data {
        InventoryFixture.effectFields(
            effect: effect.effect,
            magnitude: effect.magnitude,
            area: 0,
            duration: effect.duration
        ) + effect.conditions
    }

    /// ALCH ENIT: value, flags, addiction, chance, sound.
    private static var enit: Data {
        var data = Data()
        for _ in 0 ..< 5 {
            data.appendUInt32(0)
        }
        return data
    }

    private static func floatData(_ value: Float) -> Data {
        var data = Data()
        data.appendUInt32(value.bitPattern)
        return data
    }
}

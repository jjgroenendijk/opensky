// Synthetic MGEF, ALCH and INGR fixtures for the active-effect suites. The MGEF
// DATA layout is UESP "Skyrim Mod:Mod File Format/MGEF": 152 bytes, with flags
// at 0x00, associated item 0x08, second actor-value weight 0x3C, archetype
// 0x40, primary actor value 0x44, and second actor value 0x58.

@testable import FormatsCoreTesting
import FormatsESMTesting
import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData

@MainActor
public enum ActiveEffectFixture {
    public static let pluginName = "Base.esm"

    /// Restore Health: value modifier, health, not detrimental, no Recover.
    public static let restoreHealth: UInt32 = 0x10
    /// Damage Health: value modifier, health, detrimental.
    public static let damageHealth: UInt32 = 0x11
    /// Fortify Resist Fire: value modifier on a non-primary value with
    /// Recover set, which is the archetype's held-modifier behaviour.
    public static let fortifyResistFire: UInt32 = 0x12
    /// A dual value modifier over resist fire and resist frost.
    public static let dualResist: UInt32 = 0x13
    /// An archetype this milestone does not implement.
    public static let paralyze: UInt32 = 0x14
    /// A peak value modifier sharing keyword 0x900.
    public static let peakResist: UInt32 = 0x15
    /// Fortify Health: value modifier on health with Recover set — a held
    /// modifier on a primary.
    public static let fortifyHealth: UInt32 = 0x16

    public static let stackKeyword: UInt32 = 0x900

    /// One MGEF DATA block. Every field this milestone reads is a parameter;
    /// the rest are zero, which is a valid record and keeps the fixture honest
    /// about what the planner actually consumes.
    public static func data(
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

    public static func magicEffect(
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

    /// The seven effects every suite shares.
    public static var effectRecords: [Data] {
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
            ),
            magicEffect(
                formID: fortifyHealth, editorID: "FortifyHealth", name: "Fortify Health",
                data: data(flags: [.recover], archetype: 0, primaryValue: 24)
            )
        ]
    }

    public struct EffectSpec {
        public let effect: UInt32
        public let magnitude: Float
        public let duration: UInt32
        public let conditions: Data

        public init(
            _ effect: UInt32,
            magnitude: Float,
            duration: UInt32 = 0,
            conditions: Data = Data()
        ) {
            self.effect = effect
            self.magnitude = magnitude
            self.duration = duration
            self.conditions = conditions
        }
    }

    public static func ingestible(
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

    public static func ingredient(
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

    public static func plugin(records: [Data]) throws -> ESMFile {
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

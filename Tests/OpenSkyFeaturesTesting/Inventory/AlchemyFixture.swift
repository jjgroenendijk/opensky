// The inventory fixture plugin plus three MGEF, three INGR, and one poison ALCH, so
// the alchemy suites can brew by hand-computable numbers. Every byte is built here.

import Foundation
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
import OpenSkyInventoryInterface

public enum AlchemyFixture {
    public static let pluginName = "Skyrim.esm"

    /// Base cost 0.5, power scales the magnitude.
    public static let restoreHealth = FormID(0x0000_6000)
    /// Base cost 3, hostile, power scales the magnitude.
    public static let damageHealth = FormID(0x0000_6010)
    /// Base cost 1, power scales magnitude and duration.
    public static let fortifySmithing = FormID(0x0000_6020)

    /// Restore Health 1, Damage Health 1.
    public static let wheat = FormID(0x0000_7000)
    /// Restore Health 2, Fortify Smithing 1 for 60 s.
    public static let flower = FormID(0x0000_7010)
    /// Damage Health 1, Fortify Smithing 1 for 60 s.
    public static let cap = FormID(0x0000_7020)
    /// Fortify Smithing 1 for 60 s only, so it shares nothing with wheat.
    public static let salt = FormID(0x0000_7030)
    /// Damage Health 10, with the Poison flag.
    public static let poison = FormID(0x0000_7100)

    public static func pluginBytes() -> Data {
        InventoryBaselineFixture.pluginBytes()
            + ESMFixture.topGroup("MGEF", contents: effectRecords())
            + ESMFixture.topGroup("INGR", contents: ingredientRecords())
            + ESMFixture.topGroup("ALCH", contents: poisonRecord())
    }

    public static func file() throws -> ESMFile {
        try ESMFile(data: pluginBytes())
    }

    public static func resolver() throws -> InventoryBaselineResolver {
        try InventoryBaselineResolver.build(from: file())
    }

    public static func effects() throws -> MagicEffectStore {
        try MagicEffectStore(plugins: [(pluginName, file())])
    }

    private static func effectRecords() -> Data {
        let scalesMagnitude: MagicEffectFlags = [.powerAffectsMagnitude]
        return effect(restoreHealth, "AlchRestoreHealth", "Restore Health", 0.5, scalesMagnitude)
            + effect(
                damageHealth, "AlchDamageHealth", "Damage Health", 3,
                [.hostile, .detrimental, .powerAffectsMagnitude]
            )
            + effect(
                fortifySmithing, "AlchFortifySmithing", "Fortify Smithing", 1,
                [.powerAffectsMagnitude, .powerAffectsDuration]
            )
    }

    private static func effect(
        _ id: FormID, _ editorID: String, _ name: String, _ cost: Float, _ flags: MagicEffectFlags
    ) -> Data {
        ESMFixture.record(
            "MGEF",
            formID: id.rawValue,
            data: ESMFixture.field("EDID", ESMFixture.zstring(editorID))
                + ESMFixture.field("FULL", ESMFixture.zstring(name))
                + ESMFixture.field("DATA", MagicEffectFixture.data(baseCost: cost, flags: flags))
        )
    }

    private static func ingredientRecords() -> Data {
        ingredient(wheat, "Wheat", [entry(restoreHealth, 1, 0), entry(damageHealth, 1, 0)])
            + ingredient(flower, "BlueMountainFlower", [
                entry(restoreHealth, 2, 0), entry(fortifySmithing, 1, 60)
            ])
            + ingredient(cap, "BleedingCrown", [
                entry(damageHealth, 1, 0), entry(fortifySmithing, 1, 60)
            ])
            + ingredient(salt, "Salt", [entry(fortifySmithing, 1, 60)])
    }

    private static func entry(_ effect: FormID, _ magnitude: Float, _ duration: UInt32)
        -> MagicItemEffect
    {
        MagicItemEffect(effect: effect, magnitude: magnitude, area: 0, duration: duration)
    }

    private static func ingredient(
        _ id: FormID, _ editorID: String, _ effects: [MagicItemEffect]
    ) -> Data {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring(editorID))
            + ESMFixture.field("FULL", ESMFixture.zstring(editorID))
            + ESMFixture.field("DATA", InventoryFixture.valueWeightData(value: 2, weight: 0.1))
        var enit = Data()
        enit.appendUInt32(2)
        enit.appendUInt32(0)
        fields += ESMFixture.field("ENIT", enit)
        for effect in effects {
            fields += InventoryFixture.effectFields(
                effect: effect.effect.rawValue, magnitude: effect.magnitude, area: 0,
                duration: effect.duration
            )
        }
        return ESMFixture.record("INGR", formID: id.rawValue, data: fields)
    }

    private static func poisonRecord() -> Data {
        var weight = Data()
        weight.appendFloat32(0.5)
        let fields = ESMFixture.field("EDID", ESMFixture.zstring("DamageHealthPoison"))
            + ESMFixture.field("FULL", ESMFixture.zstring("Damage Health Poison"))
            + ESMFixture.field("DATA", weight)
            + ESMFixture.field(
                "ENIT", InventoryFixture.enitData(
                    value: 20,
                    flags: Ingestible.Flags.poison.rawValue
                )
            )
            + InventoryFixture.effectFields(
                effect: damageHealth.rawValue, magnitude: 10, area: 0, duration: 0
            )
        return ESMFixture.record("ALCH", formID: poison.rawValue, data: fields)
    }
}

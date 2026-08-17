// Synthetic ENCH, MGEF, FLST, WEAP and ARMO fixtures for the enchantment-runtime
// suites (issue #472, roadmap item 19.9). Every byte is authored here; nothing
// comes from the game install (AGENTS.md "Legal & IP boundary").
//
// The shapes mirror what the real records carry, which is measured rather than
// guessed — see `ItemEnchantmentProfile` for the counts: an armour enchantment is
// `constant effect / self` and a weapon's is `fire and forget / touch`.
//
// The numbers are chosen so every assertion is hand-computable. The blade's
// enchantment carries a manual cost of 18 and the blade an EAMT of 90, so it has
// exactly five uses — the same `floor(charge / cost)` the real-data suite pins
// against UESP's published rows.

import Foundation
@testable import opensky
import Testing

@MainActor
enum EnchantmentRuntimeFixture {
    static let pluginName = "Base.esm"

    /// Damage Health: value modifier, health, detrimental, no Recover — so a
    /// contact hit takes health off once.
    static let damageHealth: UInt32 = 0x50
    /// Fortify One-Handed: peak value modifier with Recover, on One-Handed
    /// Modifier, which is the value the vanilla enchantment moves.
    static let fortifyOneHanded: UInt32 = 0x52
    /// Fortify Block: the same shape on Block Modifier.
    static let fortifyBlock: UInt32 = 0x53

    /// The contact enchantment the blade carries.
    static let weaponEnchantment: UInt32 = 0x42
    /// The constant-effect enchantment the ring carries, worn-restricted to
    /// `ringKeyword`.
    static let ringEnchantment: UInt32 = 0x43
    /// The constant-effect enchantment the shield carries, unrestricted.
    static let shieldEnchantment: UInt32 = 0x44

    static let restrictionList: UInt32 = 0x91
    static let ringKeyword: UInt32 = 0x800
    static let shieldKeyword: UInt32 = 0x801

    static let enchantedBlade: UInt32 = 0x500
    static let plainBlade: UInt32 = 0x600
    static let enchantedRing: UInt32 = 0x700
    static let enchantedShield: UInt32 = 0x701

    /// EAMT on the blade, and the manual ENIT cost of its enchantment. 90 / 18
    /// is five uses exactly.
    static let bladeCharge: UInt16 = 90
    static let bladeCostPerUse: Int32 = 18
    static let bladeUses = 5

    /// Magnitude of the blade's damage-health entry.
    static let bladeDamage: Float = 5
    /// Magnitude of the ring's Fortify One-Handed entry, in percentage points.
    static let ringFortifyPoints: Float = 20
    /// Magnitude of the shield's Fortify Block entry.
    static let shieldFortifyPoints: Float = 25

    // MARK: - Records

    /// One MGEF, with the base cost and the archetype/actor-value fields the
    /// planner reads. Built on `ActiveEffectFixture.data`'s layout with the base
    /// cost written into the word UESP's MGEF DATA table puts it in (0x04).
    struct EffectSpec {
        let formID: UInt32
        let editorID: String
        let flags: MagicEffectFlags
        let archetype: UInt32
        let primaryValue: Int32
        let baseCost: Float

        init(
            formID: UInt32,
            editorID: String,
            flags: MagicEffectFlags,
            archetype: UInt32,
            primaryValue: Int32,
            baseCost: Float = 10
        ) {
            self.formID = formID
            self.editorID = editorID
            self.flags = flags
            self.archetype = archetype
            self.primaryValue = primaryValue
            self.baseCost = baseCost
        }
    }

    static func magicEffect(_ spec: EffectSpec, name: String) -> Data {
        let formID = spec.formID
        let editorID = spec.editorID
        let baseCost = spec.baseCost
        var data = ActiveEffectFixture.data(
            flags: spec.flags,
            archetype: spec.archetype,
            primaryValue: spec.primaryValue
        )
        data.replaceSubrange(4 ..< 8, with: withUnsafeBytes(of: baseCost.bitPattern.littleEndian) {
            Data($0)
        })
        return ESMFixture.record(
            "MGEF",
            formID: formID,
            data: ESMFixture.field("EDID", ESMFixture.zstring(editorID))
                + ESMFixture.field("FULL", ESMFixture.zstring(name))
                + ESMFixture.field("DATA", data)
        )
    }

    static var effectRecords: [Data] {
        [
            magicEffect(
                EffectSpec(
                    formID: damageHealth,
                    editorID: "TestDamageHealthContact",
                    flags: [.detrimental, .hostile],
                    archetype: 0,
                    primaryValue: 24
                ),
                name: "Damage Health"
            ),
            magicEffect(
                EffectSpec(
                    formID: fortifyOneHanded,
                    editorID: "TestFortifyOneHanded",
                    flags: [.recover],
                    archetype: 34,
                    primaryValue: CombatFortifyBonusIndices.oneHanded
                ),
                name: "Fortify One-Handed"
            ),
            magicEffect(
                EffectSpec(
                    formID: fortifyBlock,
                    editorID: "TestFortifyBlock",
                    flags: [.recover],
                    archetype: 34,
                    primaryValue: CombatFortifyBonusIndices.block
                ),
                name: "Fortify Block"
            )
        ]
    }

    static var enchantmentRecords: [Data] {
        [
            EnchantmentFixture.record(
                formID: weaponEnchantment,
                editorID: "TestEnchWeaponFire",
                name: "Burning",
                enit: EnchantmentFixture.enit(
                    cost: bladeCostPerUse,
                    flags: EnchantmentFlags.manualCostCalc.rawValue,
                    castingType: 1,
                    amount: Int32(bladeCharge),
                    delivery: 1,
                    type: 6,
                    wornRestrictions: 0
                ),
                effects: [.init(damageHealth, magnitude: bladeDamage)]
            ),
            EnchantmentFixture.record(
                formID: ringEnchantment,
                editorID: "TestEnchRingOneHanded",
                name: "Wielding",
                enit: EnchantmentFixture.enit(
                    cost: 0,
                    flags: EnchantmentFlags.manualCostCalc.rawValue,
                    castingType: 0,
                    delivery: 0,
                    type: 6,
                    wornRestrictions: restrictionList
                ),
                effects: [.init(fortifyOneHanded, magnitude: ringFortifyPoints)]
            ),
            EnchantmentFixture.record(
                formID: shieldEnchantment,
                editorID: "TestEnchShieldBlock",
                name: "Blocking",
                enit: EnchantmentFixture.enit(
                    cost: 0,
                    flags: EnchantmentFlags.manualCostCalc.rawValue,
                    castingType: 0,
                    delivery: 0,
                    type: 6,
                    wornRestrictions: 0
                ),
                effects: [.init(fortifyBlock, magnitude: shieldFortifyPoints)]
            )
        ]
    }

    /// A one-handed sword's DNAM: animation type 1, which is what makes the
    /// swing read the One-Handed fortify values rather than the two-handed ones.
    static var oneHandedDNAM: Data {
        InventoryFixture.weaponDNAM(animation: 1, speed: 1, reach: 1, flags: 0, skill: 6)
    }

    static var itemRecords: [Data] {
        [
            ESMFixture.record(
                "WEAP",
                formID: enchantedBlade,
                data: ESMFixture.field("EDID", ESMFixture.zstring("TestEnchantedBlade"))
                    + InventoryFixture.formIDField("EITM", weaponEnchantment)
                    + ESMFixture.field("EAMT", EnchantmentFixture.chargeField(bladeCharge))
                    + ESMFixture.field("DATA", InventoryFixture.weaponData(
                        value: 100, weight: 12, damage: 10
                    ))
                    + ESMFixture.field("DNAM", oneHandedDNAM)
            ),
            ESMFixture.record(
                "WEAP",
                formID: plainBlade,
                data: ESMFixture.field("EDID", ESMFixture.zstring("TestPlainBlade"))
                    + ESMFixture.field("DATA", InventoryFixture.weaponData(
                        value: 25, weight: 9, damage: 10
                    ))
                    + ESMFixture.field("DNAM", oneHandedDNAM)
            ),
            ESMFixture.record(
                "ARMO",
                formID: enchantedRing,
                data: ESMFixture.field("EDID", ESMFixture.zstring("TestEnchantedRing"))
                    + InventoryFixture.formIDField("EITM", ringEnchantment)
                    + InventoryFixture.keywordFields([ringKeyword])
                    + ESMFixture.field("DATA", InventoryFixture.valueWeightData(
                        value: 200, weight: 1
                    ))
            ),
            ESMFixture.record(
                "ARMO",
                formID: enchantedShield,
                data: ESMFixture.field("EDID", ESMFixture.zstring("TestEnchantedShield"))
                    + InventoryFixture.formIDField("EITM", shieldEnchantment)
                    + InventoryFixture.keywordFields([shieldKeyword])
                    + ESMFixture.field("DATA", InventoryFixture.valueWeightData(
                        value: 300, weight: 12
                    ))
            ),
            ESMFixture.record(
                "FLST",
                formID: restrictionList,
                data: ESMFixture.field("EDID", ESMFixture.zstring("TestEnchantmentRings"))
                    + InventoryFixture.formIDField("LNAM", ringKeyword)
            )
        ]
    }

    static func plugin() throws -> ESMFile {
        try SpellStoreFixture.plugin(
            records: effectRecords + enchantmentRecords + itemRecords
        )
    }

    // MARK: - Assembled world

    /// Everything a runtime test needs: the effect runtime over a fresh store,
    /// the ENCH index, and the item index the profiles are resolved from.
    struct World {
        var effects: ActiveEffectRuntime
        let store: WorldStateStore
        let enchantments: EnchantmentStore
        let items: ItemDefinitionStore

        /// The resolved profile of one item, which every test starts from.
        func profile(of item: UInt32) throws -> ItemEnchantmentProfile {
            let definition = try #require(items.definition(FormID(item)))
            return try #require(ItemEnchantmentProfile.resolve(definition, using: enchantments))
        }
    }

    static func world() throws -> World {
        let file = try plugin()
        let index = RecordIndex(
            plugins: [(pluginName, file)],
            recordTypes: ["MGEF", "ENCH", "FLST"]
        )
        let effects = MagicEffectStore(index: index)
        let enchantments = EnchantmentStore(index: index, effects: effects)
        let store = WorldStateStore()
        let values = ActorValueRuntime(
            store: store,
            baselines: ActorValueBaselineResolver(
                fallback: ActorValueBaseline(
                    maximums: ActorValues(repeating: 100),
                    regenPercentPerSecond: .zero
                )
            )
        )
        return World(
            effects: ActiveEffectRuntime(values: values, effects: effects),
            store: store,
            enchantments: enchantments,
            items: ItemDefinitionStore(
                file: file,
                enchantments: ItemEnchantmentResolver(
                    store: enchantments,
                    pluginName: pluginName
                )
            )
        )
    }

    /// A second actor to swing at, so a hit is never applied to its own owner.
    static let target = ActorValueHolder(
        key: .plugin(name: pluginName.lowercased(), objectID: 0x1000),
        subject: .player
    )
}

/// The actor-value indices the fortify fixtures name, resolved through the
/// vanilla table rather than written as numbers — the same rule
/// `CombatFortifyBonus` follows.
@MainActor
enum CombatFortifyBonusIndices {
    static let oneHanded = ActorValueIdentity.index(named: "One-Handed Modifier") ?? -1
    static let block = ActorValueIdentity.index(named: "Block Modifier") ?? -1
}

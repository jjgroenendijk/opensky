// The enchantment runtime against the user's own read-only install (issue #472,
// roadmap item 19.9): the two facts the runtime is built on, measured rather than
// assumed.
//
// 1. **The charge model.** UESP's "Skyrim:Generic Magic Weapons" prints a
//    "Charge/Cost = Uses" column for every randomly generated magic weapon and
//    states its numbers are "base values, equivalent to the values for a player
//    with 0 in all skills"
//    (<https://en.uesp.net/wiki/Skyrim:Generic_Magic_Weapons>). Five of its rows
//    are pinned here against the records: the weapon's `EAMT`, the enchantment's
//    resolved cost, and `floor(charge / cost)`. If a decode or the cost formula
//    ever drifts, this fails rather than a charge quietly meaning something else.
//
// 2. **The worn restriction is not a runtime gate.** The Creation Kit wiki
//    describes it as an authoring restriction, and the records agree: a
//    measurable minority of enchanted ARMO records carry no keyword their own
//    enchantment's restriction list names. Those counterexamples are asserted to
//    still exist, so nothing can quietly start enforcing the list and silently
//    strip effects off vanilla artifacts.
//
// Read-only and headless: counts, editor IDs and shapes only, so no game bytes
// leave the machine (AGENTS.md "Legal & IP boundary").

import Foundation
@testable import opensky
import Testing

struct EnchantmentRuntimeRealDataTests {
    private static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty
        else { return nil }
        return try? GameDataLocator.locate()
    }()

    /// One UESP row: the weapon, and the three numbers its table prints.
    private struct ChargePin {
        let objectID: UInt32
        let name: String
        let charge: Int
        let cost: Int
        let uses: Int
    }

    private static let chargePins = [
        ChargePin(
            objectID: 0x000A_CC70,
            name: "Dwarven Warhammer of Absorption",
            charge: 1000, cost: 18, uses: 55
        ),
        ChargePin(
            objectID: 0x000B_F3D0,
            name: "Ebony Battleaxe of the Vampire",
            charge: 3000, cost: 109, uses: 27
        ),
        ChargePin(
            objectID: 0x0008_9708,
            name: "Iron Battleaxe of Dismay",
            charge: 500, cost: 7, uses: 71
        ),
        ChargePin(
            objectID: 0x000A_BB0E,
            name: "Imperial Bow of Cowardice",
            charge: 300, cost: 11, uses: 27
        ),
        ChargePin(
            objectID: 0x000B_D818,
            name: "Elven Battleaxe of Banishing",
            charge: 2000, cost: 138, uses: 14
        )
    ]

    @Test(.enabled(if: Self.dataRoot != nil))
    func chargeModelMatchesThePublishedUsesForEveryPinnedWeapon() throws {
        let root = try #require(Self.dataRoot)
        let index = RecordIndex(
            plugins: ActivePluginFiles.load(root: root),
            recordTypes: ["MGEF", "ENCH", "WEAP"]
        )
        let store = EnchantmentStore(index: index, effects: MagicEffectStore(index: index))
        let weapons = index.definitions(of: "WEAP")
        var checked = 0
        for pin in Self.chargePins {
            let indexed = try #require(
                weapons.first { $0.record.formID == pin.objectID },
                "\(pin.name) is not in this load order"
            )
            let weapon = try Weapon(record: indexed.record, localized: indexed.localized)
            let link = try #require(weapon.enchantment)
            let enchantment = try #require(store.resolve(link, fromPlugin: indexed.sourcePlugin))
            let charge = EnchantmentCharge(
                capacity: Float(weapon.enchantmentCharge ?? 0),
                costPerUse: Float(enchantment.cost.cost)
            )
            #expect(Int(charge.capacity) == pin.charge, "\(pin.name) charge")
            #expect(Int(charge.costPerUse) == pin.cost, "\(pin.name) cost")
            #expect(charge.usesRemaining == pin.uses, "\(pin.name) uses")
            checked += 1
        }
        #expect(checked == Self.chargePins.count)
    }

    /// Every enchanted weapon in the load order resolves a profile with a contact
    /// delivery or is a staff, and every enchanted piece of armour resolves a worn
    /// one. That is the classification the two runtime paths switch on, so a record
    /// shape this engine does not expect would show up here as a count.
    @Test(.enabled(if: Self.dataRoot != nil))
    func everyEnchantedItemClassifiesAsWornContactOrStaff() throws {
        let root = try #require(Self.dataRoot)
        let plugins = ActivePluginFiles.load(root: root)
        let baseName = try #require(plugins.first?.name)
        let index = RecordIndex(
            plugins: plugins,
            recordTypes: ["MGEF", "ENCH", "WEAP", "ARMO"]
        )
        let enchantments = EnchantmentStore(
            index: index,
            effects: MagicEffectStore(index: index)
        )
        let items = try ItemDefinitionStore(
            file: ESMFile(url: root.dataURL.appending(path: baseName)),
            enchantments: ItemEnchantmentResolver(store: enchantments, pluginName: baseName)
        )
        var worn = 0
        var contact = 0
        var staff = 0
        var unclassified: [String] = []
        for definition in items.definitions.values where definition.enchantment != nil {
            guard
                let profile = ItemEnchantmentProfile.resolve(definition, using: enchantments)
            else { continue }
            switch (profile.isWorn, profile.isContact, profile.isStaff) {
            case (true, _, _): worn += 1
            case (_, true, _): contact += 1
            case (_, _, true): staff += 1
            default: unclassified.append(definition.editorID ?? definition.formID.description)
            }
        }
        #expect(worn > 0)
        #expect(contact > 0)
        #expect(staff > 0)
        #expect(unclassified.isEmpty, "unclassified: \(unclassified.prefix(8))")
        print(
            "[INFO] enchanted items: \(worn) worn, \(contact) contact, \(staff) staff, "
                + "\(unclassified.count) unclassified"
        )
    }

    /// The measurement that settles why the worn restriction gates nothing at
    /// runtime: some vanilla enchanted armour does not satisfy its own list.
    @Test(.enabled(if: Self.dataRoot != nil))
    func someVanillaArmorFailsItsOwnWornRestriction() throws {
        let root = try #require(Self.dataRoot)
        let index = RecordIndex(
            plugins: ActivePluginFiles.load(root: root),
            recordTypes: ["MGEF", "ENCH", "ARMO", "FLST"]
        )
        let store = EnchantmentStore(index: index, effects: MagicEffectStore(index: index))
        var lists: [UInt32: FormList] = [:]
        for indexed in index.definitions(of: "FLST") {
            guard let list = try? FormList(record: indexed.record) else { continue }
            lists[indexed.record.formID] = list
        }
        var restricted = 0
        var failing: [String] = []
        for indexed in index.definitions(of: "ARMO") {
            guard
                let armor = try? Armor(record: indexed.record, localized: indexed.localized),
                let link = armor.enchantment,
                let enchantment = store.resolve(link, fromPlugin: indexed.sourcePlugin),
                let restriction = store.baseChain(of: enchantment.id)
                    .lazy.compactMap({ $0.data?.wornRestrictions }).first,
                let list = lists[restriction.rawValue]
            else { continue }
            restricted += 1
            let profile = ItemEnchantmentProfile(
                item: armor.formID,
                enchantment: ReferenceKey(resolved: enchantment.id),
                sourcePlugin: enchantment.sourcePlugin,
                entries: enchantment.record.effects,
                name: enchantment.displayName,
                castingType: enchantment.data?.castingType ?? .constantEffect,
                delivery: enchantment.data?.delivery ?? .selfTarget,
                type: enchantment.data?.type ?? .enchantment,
                capacity: 0,
                costPerUse: 0,
                wornRestriction: restriction
            )
            guard
                !profile.allowsWearing(
                    keywords: armor.keywords.keywords,
                    listedKeywords: list.entries.compactMap(\.self)
                ) else { continue }
            failing.append(armor.editorID ?? armor.formID.description)
        }
        #expect(restricted > 1000)
        // Non-empty is the whole point: enforcing the list would strip the effects
        // off every one of these, so the runtime must not consult it.
        #expect(!failing.isEmpty)
        #expect(failing.contains("dunGauldurAmulet"))
        print(
            "[INFO] ARMO with a worn restriction \(restricted), "
                + "failing their own list \(failing.count)"
        )
    }
}

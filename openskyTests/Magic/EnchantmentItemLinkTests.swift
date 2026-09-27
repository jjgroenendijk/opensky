// The EITM links that reach an item: the enchantment named in a WEAP and ARMO
// summary, and the resolved enchantment threaded onto their item definitions.
// The store itself is covered in EnchantmentStoreTests.

import Foundation
@testable import opensky
import Testing

struct EnchantmentItemLinkTests {
    /// The links on WEAP and ARMO name their enchantment in a dump, and the
    /// weapon's EAMT charge prints beside it.
    @Test
    func weaponAndArmorSummariesNameTheirEnchantment() throws {
        let file = try EnchantmentFixture.itemPlugin()
        let context = try EnchantmentFixture.inspectorContext(for: file)

        let weaponDump = try RecordTextDump.dump(
            record: SpellStoreFixture.firstRecord(type: "WEAP", in: file),
            localized: false,
            magicInspectorContext: context
        )
        #expect(weaponDump.contains("enchantment Burning, charge 1500"))

        let armorDump = try RecordTextDump.dump(
            record: SpellStoreFixture.firstRecord(type: "ARMO", in: file),
            localized: false,
            magicInspectorContext: context
        )
        #expect(armorDump.contains("enchantment Burning"))
        #expect(!armorDump.contains("charge"))
    }

    /// Item definitions carry the link and, with a resolver, the winning ENCH
    /// identity — so the equipment runtime does not re-walk plugins.
    @Test
    func itemDefinitionsCarryTheResolvedEnchantment() throws {
        let file = try EnchantmentFixture.itemPlugin()
        let index = RecordIndex(
            plugins: [("Base.esm", file)],
            recordTypes: ["MGEF", "ENCH"]
        )
        let store = ItemDefinitionStore(
            file: file,
            enchantments: ItemEnchantmentResolver(
                store: EnchantmentStore(index: index),
                pluginName: "Base.esm"
            )
        )

        let weapon = try #require(store.definition(FormID(0x500)))
        #expect(weapon.enchantment?.link == FormID(0x42))
        #expect(weapon.enchantment?.charge == 1500)
        #expect(
            weapon.enchantment?.resolvedID
                == ResolvedFormID(plugin: "Base.esm", objectID: 0x42)
        )
        #expect(store.enchantment(of: weapon)?.editorID == "TestEnchFire")

        let armor = try #require(store.definition(FormID(0x700)))
        #expect(armor.enchantment?.link == FormID(0x42))
        #expect(armor.enchantment?.charge == nil)
        #expect(store.enchantment(of: armor)?.displayName == "Burning")
    }

    /// Without a resolver the link is still carried, just unresolved: a store
    /// built from one file alone still reports which items are enchanted.
    @Test
    func linksAreCarriedEvenWithoutAResolver() throws {
        let store = try ItemDefinitionStore(file: EnchantmentFixture.itemPlugin())
        let weapon = try #require(store.definition(FormID(0x500)))
        #expect(weapon.enchantment?.link == FormID(0x42))
        #expect(weapon.enchantment?.charge == 1500)
        #expect(weapon.enchantment?.resolvedID == nil)
        #expect(store.enchantment(of: weapon) == nil)

        let unenchanted = try #require(store.definition(FormID(0x600)))
        #expect(unenchanted.enchantment == nil)
    }
}

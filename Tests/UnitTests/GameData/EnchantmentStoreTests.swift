// Synthetic EnchantmentStore coverage: cross-plugin overrides, the resolved
// effect join, base-enchantment chains including a cyclic one, and the ENCH
// record dump. The EITM links that reach an item live in
// EnchantmentItemLinkTests.

import Foundation
@testable import opensky
import Testing

struct EnchantmentStoreTests {
    @Test
    func joinsEffectsAndCostsThemLikeASpell() throws {
        let store = try store(records: [
            EnchantmentFixture.record(
                formID: 0x42,
                editorID: "TestEnchFire",
                name: "Burning",
                enit: EnchantmentFixture.enit(cost: 60, amount: 1500),
                effects: [.init(0x50, magnitude: 25), .init(0x51, magnitude: 5, duration: 60)]
            )
        ])
        let enchantment = try #require(store.enchantment(editorID: "TestEnchFire"))

        // The same curve a spell uses: 10 * (25 * 10 / 10) ^ 1.1 = 344.93 and
        // 2.5 * (5 * 60 / 10) ^ 1.1 = 105.38, truncated before the sum.
        #expect(enchantment.cost.autoCalculated == 449)
        #expect(enchantment.cost.cost == 449)
        #expect(!enchantment.cost.isManual)
        #expect(enchantment.effects.map(\.displayName) == ["Fire Damage", "Fire Cloak"])
        #expect(enchantment.displayName == "Burning")
        #expect(enchantment.data?.amount == 1500)
    }

    @Test
    func manualCostFlagKeepsTheAuthoredEnchantmentCost() throws {
        let store = try store(records: [
            EnchantmentFixture.record(
                formID: 0x42,
                editorID: "TestEnchManual",
                name: "Manual",
                enit: EnchantmentFixture.enit(
                    cost: 7,
                    flags: EnchantmentFlags.manualCostCalc.rawValue
                ),
                effects: [.init(0x50, magnitude: 25)]
            )
        ])
        let enchantment = try #require(store.enchantment(editorID: "TestEnchManual"))
        #expect(enchantment.cost.isManual)
        #expect(enchantment.cost.cost == 7)
        #expect(enchantment.cost.autoCalculated == 344)
    }

    @Test
    func laterOverrideWinsAndEditorLookupIsCaseInsensitive() throws {
        let base = try SpellStoreFixture.plugin(
            records: SpellStoreFixture.effectRecords + [EnchantmentFixture.record(
                formID: 0x42,
                editorID: "BaseEnch",
                name: "Base name",
                enit: EnchantmentFixture.enit(cost: 10),
                effects: [.init(0x50, magnitude: 25)]
            )]
        )
        let patch = try SpellStoreFixture.plugin(
            masters: ["Base.esm"],
            records: [EnchantmentFixture.record(
                formID: 0x42,
                editorID: "PatchedEnch",
                name: "Winner",
                enit: EnchantmentFixture.enit(
                    cost: 3,
                    flags: EnchantmentFlags.manualCostCalc.rawValue
                ),
                effects: [.init(0x50, magnitude: 25)]
            )]
        )
        let store = EnchantmentStore(plugins: [("Base.esm", base), ("Patch.esp", patch)])

        let resolved = try #require(
            store.enchantment(ResolvedFormID(plugin: "Base.esm", objectID: 0x42))
        )
        #expect(resolved.editorID == "PatchedEnch")
        #expect(resolved.displayName == "Winner")
        #expect(resolved.sourcePlugin == "Patch.esp")
        #expect(resolved.cost.cost == 3)
        #expect(store.enchantment(editorID: "PATCHEDENCH")?.id == resolved.id)
        #expect(store.enchantment(editorID: "baseench") == nil)
        #expect(store.enchantments.count == 1)
    }

    @Test
    func baseEnchantmentChainIsFollowedNearestFirst() throws {
        let store = try store(records: [
            EnchantmentFixture.record(
                formID: 0x42,
                editorID: "EnchFireDamage03",
                name: "Burning",
                enit: EnchantmentFixture.enit(cost: 60, baseEnchantment: 0x43),
                effects: [.init(0x50, magnitude: 25)]
            ),
            EnchantmentFixture.record(
                formID: 0x43,
                editorID: "EnchFireDamageBase",
                name: "Burning",
                enit: EnchantmentFixture.enit(cost: 0, wornRestrictions: 0x60)
            )
        ])
        let leaf = try #require(store.enchantment(editorID: "EnchFireDamage03"))
        let chain = store.baseChain(of: leaf.id)
        #expect(chain.map(\.editorID) == ["EnchFireDamage03", "EnchFireDamageBase"])
        #expect(chain.last?.data?.wornRestrictions == FormID(0x60))
        #expect(store.baseChain(of: ResolvedFormID(plugin: "Base.esm", objectID: 0xFF)).isEmpty)
    }

    /// A mod can point two enchantments at each other. The chain has to stop
    /// rather than recurse; each identity appears once.
    @Test
    func cyclicBaseEnchantmentChainTerminates() throws {
        let store = try store(records: [
            EnchantmentFixture.record(
                formID: 0x42,
                editorID: "EnchLoopA",
                name: "A",
                enit: EnchantmentFixture.enit(baseEnchantment: 0x43)
            ),
            EnchantmentFixture.record(
                formID: 0x43,
                editorID: "EnchLoopB",
                name: "B",
                enit: EnchantmentFixture.enit(baseEnchantment: 0x42)
            )
        ])
        let start = try #require(store.enchantment(editorID: "EnchLoopA"))
        let chain = store.baseChain(of: start.id)
        #expect(chain.map(\.editorID) == ["EnchLoopA", "EnchLoopB"])
        #expect(chain.count < EnchantmentStore.chainCap)
    }

    @Test
    func enchantmentDumpNamesItsEffectsAndItsLinks() throws {
        let file = try SpellStoreFixture.plugin(
            records: SpellStoreFixture.effectRecords + [
                EnchantmentFixture.record(
                    formID: 0x42,
                    editorID: "TestEnchFire",
                    name: "Burning",
                    enit: EnchantmentFixture.enit(
                        cost: 60,
                        amount: 1500,
                        baseEnchantment: 0x43
                    ),
                    effects: [.init(0x50, magnitude: 25)]
                ),
                EnchantmentFixture.record(
                    formID: 0x43,
                    editorID: "TestEnchFireBase",
                    name: "Burning base",
                    enit: EnchantmentFixture.enit()
                )
            ]
        )
        let dump = try RecordTextDump.dump(
            record: SpellStoreFixture.firstRecord(type: "ENCH", in: file),
            localized: false,
            magicInspectorContext: EnchantmentFixture.inspectorContext(for: file)
        )

        #expect(dump.contains("decoded ENCH: editorID TestEnchFire"))
        #expect(dump.contains("type enchantment"))
        #expect(dump.contains("delivery touch"))
        #expect(dump.contains("amount 1500"))
        #expect(dump.contains("base enchantment Burning base"))
        #expect(dump.contains("cost 344 (auto-calc"))
        #expect(dump.contains("Fire Damage — magnitude 25.00"))
    }

    // MARK: - Fixtures

    private func store(records: [Data]) throws -> EnchantmentStore {
        let file = try SpellStoreFixture.plugin(
            records: SpellStoreFixture.effectRecords + records
        )
        return EnchantmentStore(plugins: [("Base.esm", file)])
    }
}

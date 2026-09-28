// Synthetic SpellStore coverage: cross-plugin overrides, editor-id lookup, the
// auto-calculated cost against hand-computed values, and the manual-cost flag.
// The BOOK and WEAP links that resolve through this store are covered in
// SpellStoreLinkTests.

import Foundation
@testable import opensky
import Testing

struct SpellStoreTests {
    @Test
    func autoCalculatedCostSumsResolvedEffects() throws {
        let store = try SpellStoreFixture.store(spellFields: SpellStoreFixture.spellFields(
            editorID: "TestFirebolt",
            name: "Firebolt",
            spit: SpellFixture.spit(baseCost: 41),
            effects: [.init(0x50, magnitude: 25), .init(0x51, magnitude: 5, duration: 60)]
        ))
        let spell = try #require(store.spell(editorID: "TestFirebolt"))

        // 10 * (25 * 10 / 10) ^ 1.1 = 344.93 and 2.5 * (5 * 60 / 10) ^ 1.1 =
        // 105.38, each truncated to whole magicka before the sum.
        #expect(spell.cost.autoCalculated == 449)
        #expect(spell.cost.cost == 449)
        #expect(!spell.cost.isManual)
        #expect(spell.cost.unresolvedEffects == 0)
        #expect(spell.effects.map(\.displayName) == ["Fire Damage", "Fire Cloak"])
        #expect(abs((spell.effects.first?.cost ?? 0) - 344.932_4) < 0.05)
        #expect(spell.displayName == "Firebolt")
        #expect(spell.recordType == "SPEL")
    }

    @Test
    func manualCostFlagKeepsTheAuthoredValue() throws {
        let store = try SpellStoreFixture.store(spellFields: SpellStoreFixture.spellFields(
            editorID: "TestManual",
            name: "Manual",
            spit: SpellFixture.spit(
                baseCost: 7,
                flags: SpellFlags.manualCostCalc.rawValue
            ),
            effects: [.init(0x50, magnitude: 25)]
        ))
        let spell = try #require(store.spell(editorID: "TestManual"))

        #expect(spell.cost.isManual)
        #expect(spell.cost.cost == 7)
        // The formula total is still reported, for comparison against the
        // authored number.
        #expect(spell.cost.autoCalculated == 344)
    }

    @Test
    func unresolvedEffectLinkIsCountedRatherThanCosted() throws {
        let store = try SpellStoreFixture.store(spellFields: SpellStoreFixture.spellFields(
            editorID: "TestDangling",
            name: "Dangling",
            spit: SpellFixture.spit(),
            effects: [.init(0x50, magnitude: 25), .init(0x0F0F, magnitude: 10)]
        ))
        let spell = try #require(store.spell(editorID: "TestDangling"))

        #expect(spell.cost.unresolvedEffects == 1)
        #expect(spell.cost.autoCalculated == 344)
        #expect(spell.effects.last?.displayName.hasPrefix("[UNRESOLVED]") == true)
    }

    @Test
    func laterOverrideWinsAndEditorLookupIsCaseInsensitive() throws {
        let base = try SpellStoreFixture.plugin(
            records: SpellStoreFixture.effectRecords + [ESMFixture.record(
                "SPEL",
                formID: 0x42,
                data: SpellStoreFixture.spellFields(
                    editorID: "BaseSpell",
                    name: "Base name",
                    spit: SpellFixture.spit(),
                    effects: [.init(0x50, magnitude: 25)]
                )
            )]
        )
        let patch = try SpellStoreFixture.plugin(
            masters: ["Base.esm"],
            records: [ESMFixture.record(
                "SPEL",
                formID: 0x42,
                data: SpellStoreFixture.spellFields(
                    editorID: "PatchedSpell",
                    name: "Winner",
                    spit: SpellFixture.spit(
                        baseCost: 3,
                        flags: SpellFlags.manualCostCalc.rawValue
                    ),
                    effects: [.init(0x50, magnitude: 25)]
                )
            )]
        )
        let store = SpellStore(plugins: [("Base.esm", base), ("Patch.esp", patch)])

        let resolved = try #require(
            store.spell(ResolvedFormID(plugin: "Base.esm", objectID: 0x42))
        )
        #expect(resolved.editorID == "PatchedSpell")
        #expect(resolved.displayName == "Winner")
        #expect(resolved.sourcePlugin == "Patch.esp")
        #expect(resolved.cost.cost == 3)
        #expect(store.spell(editorID: "PATCHEDSPELL")?.id == resolved.id)
        #expect(store.spell(editorID: "basespell") == nil)
        #expect(store.spells.count == 1)
        #expect(store.scrolls.isEmpty)
    }

    @Test
    func scrollsShareTheStoreAndCarryTheirItemValue() throws {
        var fields = SpellStoreFixture.spellFields(
            editorID: "TestScroll",
            name: "Scroll of Fire",
            spit: SpellFixture.spit(castingType: 3),
            effects: [.init(0x50, magnitude: 25)]
        )
        fields += ESMFixture.field(
            "DATA",
            InventoryFixture.valueWeightData(value: 27, weight: 0.5)
        )
        let base = try SpellStoreFixture.plugin(
            records: SpellStoreFixture.effectRecords
                + [ESMFixture.record("SCRL", formID: 0x70, data: fields)]
        )
        let store = SpellStore(plugins: [("Base.esm", base)])

        let scroll = try #require(store.spell(editorID: "TestScroll"))
        #expect(scroll.recordType == "SCRL")
        #expect(store.scrolls.count == 1)
        #expect(store.spells.isEmpty)
        guard case let .scroll(record) = scroll.record else {
            Issue.record("expected a decoded SCRL")
            return
        }
        #expect(record.itemValue == ItemValue(value: 27, weight: 0.5))
        #expect(scroll.cost.cost == 344)
    }
}

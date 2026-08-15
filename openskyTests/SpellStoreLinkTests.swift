// The two links that were decoded but unresolvable before SpellStore existed:
// BOOK's spell tome and WEAP's critical effect. Both resolve to a spell name in
// a record dump, and the SPEL dump itself carries the cost and effect table.

import Foundation
@testable import opensky
import Testing

struct SpellStoreLinkTests {
    @Test
    func bookAndWeaponSpellLinksResolveToNamesInADump() throws {
        let file = try SpellStoreFixture.plugin(
            records: SpellStoreFixture.effectRecords + [spell, book, weapon]
        )
        let context = try context(for: file)

        let bookDump = try RecordTextDump.dump(
            record: SpellStoreFixture.firstRecord(type: "BOOK", in: file),
            localized: false,
            magicInspectorContext: context
        )
        #expect(bookDump.contains("teaches spell Firebolt"))

        let weaponDump = try RecordTextDump.dump(
            record: SpellStoreFixture.firstRecord(type: "WEAP", in: file),
            localized: false,
            magicInspectorContext: context
        )
        #expect(weaponDump.contains("critical effect Firebolt"))
    }

    @Test
    func spellDumpCarriesTheCastingHeaderCostAndEffectTable() throws {
        let file = try SpellStoreFixture.plugin(
            records: SpellStoreFixture.effectRecords + [spell]
        )
        let dump = try RecordTextDump.dump(
            record: SpellStoreFixture.firstRecord(type: "SPEL", in: file),
            localized: false,
            magicInspectorContext: context(for: file)
        )

        #expect(dump.contains("decoded SPEL: editorID TestFirebolt"))
        #expect(dump.contains("type spell"))
        #expect(dump.contains("casting fire and forget"))
        #expect(dump.contains("delivery aimed"))
        #expect(dump.contains("cost 344 (auto-calc"))
        #expect(dump.contains("Fire Damage — magnitude 25.00, area 0, duration 0s"))
    }

    // MARK: - Fixtures

    private var spell: Data {
        ESMFixture.record(
            "SPEL",
            formID: 0x42,
            data: SpellStoreFixture.spellFields(
                editorID: "TestFirebolt",
                name: "Firebolt",
                spit: SpellFixture.spit(),
                effects: [.init(0x50, magnitude: 25)]
            )
        )
    }

    private var book: Data {
        ESMFixture.record(
            "BOOK",
            formID: 0x80,
            data: ESMFixture.field("EDID", ESMFixture.zstring("SpellTomeFirebolt"))
                + ESMFixture.field("DATA", InventoryFixture.bookData(
                    flags: 0x04,
                    kind: 0,
                    teaches: 0x42,
                    value: 100,
                    weight: 1
                ))
        )
    }

    private var weapon: Data {
        ESMFixture.record(
            "WEAP",
            formID: 0x81,
            data: ESMFixture.field("EDID", ESMFixture.zstring("TestBlade"))
                + ESMFixture.field("DATA", InventoryFixture.weaponData(
                    value: 100,
                    weight: 12,
                    damage: 9
                ))
                + ESMFixture.field("CRDT", SpellStoreFixture.criticalData(effect: 0x42))
        )
    }

    private func context(for file: ESMFile) throws -> RecordTextDump.MagicInspectorContext {
        let index = RecordIndex(
            plugins: [("Base.esm", file)],
            recordTypes: ["MGEF", "SPEL", "SCRL", "BOOK", "WEAP"]
        )
        let effects = MagicEffectStore(index: index)
        return RecordTextDump.MagicInspectorContext(
            keywordStore: KeywordStore(index: index),
            formListStore: FormListStore(index: index),
            magicEffectStore: effects,
            spellStore: SpellStore(index: index, effects: effects),
            enchantmentStore: EnchantmentStore(index: index, effects: effects),
            sourcePlugin: "Base.esm"
        )
    }
}

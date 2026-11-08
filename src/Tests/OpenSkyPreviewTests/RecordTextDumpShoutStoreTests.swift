// Record dumps that name linked records through `ShoutStore`. In-code plugin fixtures only.

import Foundation
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
@testable import OpenSkyPreview
import Testing

struct RecordTextDumpShoutStoreTests {
    @Test
    func theShoutDumpNamesItsWordsAndSpellsInsteadOfPrintingHex() throws {
        let file = try ShoutPluginFixture.plugin()
        let dump = try dumpText(of: "SHOU", in: file)

        #expect(dump.contains("decoded SHOU: editorID FireBreath"))
        #expect(dump.contains("Y3 — spell Fire Breath I"))
        #expect(dump.contains("Toor — spell Fire Breath II"))
        #expect(!dump.contains("spell 00000B01"))
    }

    @Test
    func theWordLeveledSpellAndEquipSlotDumpsDecodeToo() throws {
        let file = try ShoutPluginFixture.plugin()

        let word = try dumpText(of: "WOOP", in: file)
        #expect(word.contains("decoded WOOP: editorID FireBreathWord1"))
        #expect(word.contains("translation \"Yol\""))

        let list = try dumpText(of: "LVSP", in: file)
        #expect(list.contains("decoded LVSP: editorID LSpellFire"))
        #expect(list.contains("level 1 — Fire Breath I"))

        let slot = try dumpText(of: "EQUP", in: file)
        #expect(slot.contains("decoded EQUP: editorID BothHands"))
        #expect(slot.contains("parents [LeftHand, RightHand]"))
        #expect(slot.contains("use all parents true"))
        #expect(slot.contains("hands both"))
    }

    // Without a magic context the summaries still decode; the links print as
    // raw FormIDs rather than being dropped.

    @Test
    func theDumpStillDecodesWithoutAMagicContext() throws {
        let file = try ShoutPluginFixture.plugin()
        let record = try SpellStoreFixture.firstRecord(type: "SHOU", in: file)

        let dump = RecordTextDump.dump(record: record, localized: false)

        #expect(dump.contains("decoded SHOU: editorID FireBreath"))
        #expect(dump.contains("00000A01 — spell 00000B01"))
    }

    private func dumpText(of type: String, in file: ESMFile) throws -> String {
        let index = RecordIndex(
            plugins: [("Base.esm", file)],
            recordTypes: RecordIndex.referenceRecordTypes
        )
        let effects = MagicEffectStore(index: index)
        let spells = SpellStore(index: index, effects: effects)
        return try RecordTextDump.dump(
            record: SpellStoreFixture.firstRecord(type: type, in: file),
            localized: false,
            magicInspectorContext: RecordTextDump.MagicInspectorContext(
                keywordStore: KeywordStore(index: index),
                formListStore: FormListStore(index: index),
                magicEffectStore: effects,
                spellStore: spells,
                enchantmentStore: EnchantmentStore(index: index, effects: effects),
                shoutStore: ShoutStore(index: index, spells: spells),
                equipSlotStore: EquipSlotStore(index: index),
                sourcePlugin: "Base.esm"
            )
        )
    }
}

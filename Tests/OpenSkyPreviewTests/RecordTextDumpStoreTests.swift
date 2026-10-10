// Record dumps that name linked records through the GameData stores: location
// keywords and alchemy effects. In-code plugin fixtures only.

import Foundation
import OpenSkyEngineTesting
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyFormatsTesting
import OpenSkyGameData
@testable import OpenSkyPreview
import Testing

struct RecordTextDumpStoreTests {
    @Test
    func recordDumpNamesResolvedLocationKeywords() throws {
        let locationFields = ESMFixture.field("EDID", ESMFixture.zstring("DumpLocation"))
            + ESMFixture.field("PNAM", ESMFixture.words([0x11]))
            + ESMFixture.field("KSIZ", ESMFixture.words([1]))
            + ESMFixture.field("KWDA", ESMFixture.words([0x40]))
        let file = try ESMFixture.plugin(records: [
            ESMFixture.record("LCTN", formID: 0x10, data: locationFields),
            ESMFixture.record(
                "KYWD",
                formID: 0x40,
                data: ESMFixture.field("EDID", ESMFixture.zstring("LocTypeDungeon"))
            )
        ])
        let index = RecordIndex(
            plugins: [("Base.esm", file)],
            recordTypes: RecordIndex.referenceRecordTypes
        )
        let key = ResolvedFormID(plugin: "Base.esm", objectID: 0x10)
        let record = try #require(index.records[key]?.record)
        let dump = RecordTextDump.dump(
            record: record,
            localized: false,
            keywordStore: KeywordStore(index: index),
            formListStore: FormListStore(index: index),
            sourcePlugin: "Base.esm"
        )

        #expect(dump.contains("decoded LCTN: editorID DumpLocation"))
        #expect(dump.contains("parent 00000011"))
        #expect(dump.contains("keywords [LocTypeDungeon]"))
    }

    @Test
    func alchemyDumpPrintsTheResolvedEffectName() throws {
        let index = try PotionIndexFixture.index().index
        let store = MagicEffectStore(index: index)
        let key = ResolvedFormID(plugin: "Patch.esp", objectID: 0x02)
        let alchemyRecord = try #require(index.records[key]?.record)

        let dump = RecordTextDump.dump(
            record: alchemyRecord,
            localized: false,
            magicInspectorContext: RecordTextDump.MagicInspectorContext(
                keywordStore: KeywordStore(index: index),
                formListStore: FormListStore(index: index),
                magicEffectStore: store,
                spellStore: SpellStore(index: index, effects: store),
                enchantmentStore: EnchantmentStore(index: index, effects: store),
                shoutStore: ShoutStore(index: index),
                equipSlotStore: EquipSlotStore(index: index),
                sourcePlugin: "Patch.esp"
            )
        )
        #expect(dump.contains("1 effects [Restore Health]"))
        #expect(!dump.contains("1 effects [00000001]"))
    }
}

// Record dumps that name linked records through the GameData stores: location
// keywords and alchemy effects. In-code plugin fixtures only.

@testable import FormatsCoreTesting
import FormatsESMTesting
import Foundation
@testable import OpenSkyEngine
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
import OpenSkyGameData
import Testing

struct RecordTextDumpStoreTests {
    @Test
    func recordDumpNamesResolvedLocationKeywords() throws {
        let locationFields = ESMFixture.field("EDID", ESMFixture.zstring("DumpLocation"))
            + ESMFixture.field("PNAM", words([0x11]))
            + ESMFixture.field("KSIZ", words([1]))
            + ESMFixture.field("KWDA", words([0x40]))
        let file = try plugin(records: [
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
        let base = try plugin(records: [
            ESMFixture.record(
                "MGEF",
                formID: 1,
                data: ESMFixture.field("EDID", ESMFixture.zstring("RestoreHealth"))
                    + ESMFixture.field("FULL", ESMFixture.zstring("Restore Health"))
                    + ESMFixture.field("DATA", MagicEffectFixture.data())
            )
        ])
        let alchemyFields = ESMFixture.field("EDID", ESMFixture.zstring("TestPotion"))
            + InventoryFixture.effectFields(effect: 1, magnitude: 10, area: 0, duration: 0)
        let child = try plugin(
            masters: ["Base.esm"],
            records: [ESMFixture.record("ALCH", formID: 0x0100_0002, data: alchemyFields)]
        )
        let index = RecordIndex(
            plugins: [("Base.esm", base), ("Patch.esp", child)],
            recordTypes: ["MGEF", "ALCH"]
        )
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

    private func plugin(masters: [String] = [], records: [Data]) throws -> ESMFile {
        let grouped = Dictionary(grouping: records) { record in
            String(bytes: record.prefix(4), encoding: .ascii) ?? "MISC"
        }
        var data = ESMFixture.tes4(masters: masters)
        for (type, groupedRecords) in grouped.sorted(by: { $0.key < $1.key }) {
            data += ESMFixture.topGroup(type, contents: groupedRecords.reduce(Data(), +))
        }
        return try ESMFile(data: data)
    }

    private func words(_ values: [UInt32]) -> Data {
        var data = Data()
        for value in values {
            data.appendUInt32(value)
        }
        return data
    }
}

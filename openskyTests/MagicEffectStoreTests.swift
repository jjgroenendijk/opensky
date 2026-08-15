// Synthetic two-plugin MGEF override and EFID resolution coverage.

import Foundation
@testable import opensky
import Testing

struct MagicEffectStoreTests {
    @Test
    func laterOverrideWinsAndEditorLookupIsCaseInsensitive() throws {
        let base = try plugin(records: [
            magicEffect(formID: 0x42, editorID: "BaseEffect", name: "Base name")
        ])
        let patch = try plugin(
            masters: ["Base.esm"],
            records: [magicEffect(formID: 0x42, editorID: "PatchedEffect", name: "Winner")]
        )
        let store = MagicEffectStore(plugins: [("Base.esm", base), ("Patch.esp", patch)])

        let resolved = try #require(
            store.effect(ResolvedFormID(plugin: "Base.esm", objectID: 0x42))
        )
        #expect(resolved.effect.editorID == "PatchedEffect")
        #expect(resolved.displayName == "Winner")
        #expect(resolved.sourcePlugin == "Patch.esp")
        #expect(store.effect(editorID: "PATCHEDEFFECT")?.id == resolved.id)
        #expect(store.effect(editorID: "baseeffect") == nil)
    }

    @Test
    func alchemyEffectResolvesAcrossTwoPluginIndexAndPrintsItsName() throws {
        let base = try plugin(records: [
            magicEffect(formID: 1, editorID: "RestoreHealth", name: "Restore Health")
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
        let alchemyRecord = try firstRecord(type: "ALCH", in: child)
        let item = try Ingestible(record: alchemyRecord, localized: false)
        let resolved = try #require(item.effects.first?.resolved(
            fromPlugin: "Patch.esp",
            using: store
        ))
        #expect(resolved.effect.editorID == "RestoreHealth")
        #expect(resolved.displayName == "Restore Health")

        let dump = RecordTextDump.dump(
            record: alchemyRecord,
            localized: false,
            magicInspectorContext: RecordTextDump.MagicInspectorContext(
                keywordStore: KeywordStore(index: index),
                formListStore: FormListStore(index: index),
                magicEffectStore: store,
                spellStore: SpellStore(index: index, effects: store),
                enchantmentStore: EnchantmentStore(index: index, effects: store),
                sourcePlugin: "Patch.esp"
            )
        )
        #expect(dump.contains("1 effects [Restore Health]"))
        #expect(!dump.contains("1 effects [00000001]"))
    }

    @Test
    func malformedOverrideFallsBackToEarlierReadableDefinition() throws {
        let base = try plugin(records: [
            magicEffect(formID: 0x42, editorID: "BaseEffect", name: "Readable")
        ])
        let patch = try plugin(
            masters: ["Base.esm"],
            records: [ESMFixture.record(
                "MGEF",
                formID: 0x42,
                data: ESMFixture.field("EDID", ESMFixture.zstring("BrokenOverride"))
                    + ESMFixture.field("DATA", Data(count: 151))
            )]
        )
        let store = MagicEffectStore(plugins: [("Base.esm", base), ("Patch.esp", patch)])

        let effect = try #require(
            store.effect(ResolvedFormID(plugin: "Base.esm", objectID: 0x42))
        )
        #expect(effect.effect.editorID == "BaseEffect")
        #expect(effect.sourcePlugin == "Base.esm")
    }

    private func plugin(masters: [String] = [], records: [Data]) throws -> ESMFile {
        let grouped = Dictionary(grouping: records) { record in
            String(bytes: record.prefix(4), encoding: .ascii) ?? "MGEF"
        }
        var data = ESMFixture.tes4(masters: masters)
        for (type, groupedRecords) in grouped.sorted(by: { $0.key < $1.key }) {
            data += ESMFixture.topGroup(type, contents: groupedRecords.reduce(Data(), +))
        }
        return try ESMFile(data: data)
    }

    private func magicEffect(formID: UInt32, editorID: String, name: String) -> Data {
        ESMFixture.record(
            "MGEF",
            formID: formID,
            data: ESMFixture.field("EDID", ESMFixture.zstring(editorID))
                + ESMFixture.field("FULL", ESMFixture.zstring(name))
                + ESMFixture.field("DATA", MagicEffectFixture.data())
        )
    }

    private func firstRecord(type: String, in file: ESMFile) throws -> ESMRecord {
        let group = try #require(file.topGroups.first { $0.recordType?.description == type })
        let child = try #require(try group.children().first)
        guard case let .record(record) = child else {
            throw ESMError.malformed("fixture child is not a record")
        }
        return record
    }
}

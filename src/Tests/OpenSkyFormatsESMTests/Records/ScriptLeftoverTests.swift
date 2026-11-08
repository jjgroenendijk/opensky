// Script fields of INFO, QUST, and MGEF: the leftovers older Creation Kit versions
// wrote, kept raw, and the scripts a magic effect runs. Synthetic records only.
// Layout: docs/formats/dialogue.md, quest-records.md, magic-records.md.

import Foundation
import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.parser))
struct ScriptLeftoverTests {
    @Test func infoKeepsEachLegacyBlockUntilItsNEXT() throws {
        var fields = ESMFixture.field("SCHR", Data([1, 2]))
        fields += ESMFixture.field("QNAM", Data([3]))
        fields += ESMFixture.field("NEXT", Data())
        fields += ESMFixture.field("NEXT", Data())
        let info = try DialogueFixture.info(fields)
        #expect(info.skipped.isEmpty)
        #expect(info.legacyScriptBlocks.map(\.header) == [Data([1, 2]), nil])
        #expect(info.legacyScriptBlocks.map(\.quest) == [Data([3]), nil])
        #expect(info.legacyScriptBlocks.map(\.isClosed) == [true, true])
    }

    @Test func questLogEntryKeepsItsLegacyFields() throws {
        var fields = QuestFixture.stage(10)
        fields += QuestFixture.logEntry(text: "entry")
        fields += ESMFixture.field("SCHR", Data([1]))
        fields += ESMFixture.field("SCTX", Data([2]))
        fields += ESMFixture.field("QNAM", Data([3]))
        let quest = try QuestFixture.quest(fields: fields)
        #expect(quest.skipped.total == 0)
        #expect(quest.stages.first?.logEntries.first?.legacyFields == [
            Data([1]), Data([2]), Data([3])
        ])
    }

    @Test func magicEffectReadsItsScripts() throws {
        let script = VMADFixture.Script("EffectScript", properties: [])
        let vmad = ESMFixture.field("VMAD", VMADFixture.payload(scripts: [script]))
        let bytes = ESMFixture.record("MGEF", formID: 0x42, data: vmad)
        let effect = try MagicEffect(record: ESMFixture.parseRecord(bytes), localized: false)
        #expect(effect.skipped.isEmpty)
        #expect(effect.scriptData.scripts.map(\.name) == ["EffectScript"])
    }
}

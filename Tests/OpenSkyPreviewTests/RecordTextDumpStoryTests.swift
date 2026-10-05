// The dialogue-branch, scene, and story-manager views in the Asset Browser.

import FormatsTesting
import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyPreview
import Testing

struct RecordTextDumpStoryTests {
    private typealias Fixture = ESMFixture

    @Test func dumpsBranchFlagsAndStartingTopic() throws {
        let dump = try RecordTextDump.dump(record: Fixture.record("DLBR", fields: [
            ("EDID", Fixture.zstring("GuardBranch")),
            ("QNAM", Fixture.u32(0x10)), ("TNAM", Fixture.u32(0)),
            ("DNAM", Fixture.u32(0x03)), ("SNAM", Fixture.u32(0x20))
        ]), localized: false)
        #expect(dump.contains(
            "decoded DLBR: editorID GuardBranch, quest 00000010, flags top-level blocking, "
                + "starting topic 00000020"
        ))
    }

    @Test func dumpsSceneShape() throws {
        let dump = try RecordTextDump.dump(record: Fixture.record("SCEN", fields: [
            ("EDID", Fixture.zstring("InnScene")), ("FNAM", Fixture.u32(0x02)),
            ("HNAM", Data()), ("NAM0", Fixture.zstring("Talk")), ("NEXT", Data()),
            ("NEXT", Data()), ("HNAM", Data()),
            ("ALID", Fixture.i32(0)),
            ("ANAM", Fixture.u16(2)), ("INAM", Fixture.u32(1)), ("SNAM", Fixture.u32(0)),
            ("ENAM", Fixture.u32(0)), ("SNAM", Fixture.f32(4)), ("ANAM", Data()),
            ("PNAM", Fixture.u32(0x10))
        ]), localized: false)
        #expect(dump.contains(
            "decoded SCEN: editorID InnScene, quest 00000010, phases 1, actors 1, "
                + "actions [timer 1], flags 0x2"
        ))
    }

    @Test func dumpsQuestNodeAndEventNode() throws {
        let quest = try RecordTextDump.dump(record: Fixture.record("SMQN", fields: [
            ("PNAM", Fixture.u32(0x30)),
            ("DNAM", Fixture.u32(0x0002_0000)), ("QNAM", Fixture.u32(1)), (
                "NNAM",
                Fixture.u32(0x10)
            )
        ]), localized: false)
        #expect(quest.contains(
            "decoded SMQN: editorID -, parent 00000030, previous sibling -, conditions 0, "
                + "flags 0x20000, quests [00000010]"
        ))
        let event = try RecordTextDump.dump(record: Fixture.record("SMEN", fields: [
            ("DNAM", Fixture.u32(0)), ("ENAM", Data("KILL".utf8))
        ]), localized: false)
        #expect(
            event.contains("decoded SMEN: editorID -, parent -, previous sibling -, conditions 0, "
                + "flags 0x0, event KILL")
        )
    }
}

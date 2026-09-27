// Direct ALFL quest-alias integration over synthetic records only.

import Foundation
@testable import opensky
import Testing

@MainActor
struct QuestLocationAliasTests {
    @Test func aStartFillsSpecificLocationAliases() throws {
        let locationRecord = ESMFixture.record(
            "LCTN",
            formID: 0x0500,
            data: ESMFixture.field("EDID", ESMFixture.zstring("TestLocation"))
        )
        let locationFile = try ESMFile(
            data: ESMFixture.tes4()
                + ESMFixture.topGroup("LCTN", contents: locationRecord)
        )
        let locations = LocationStore(plugins: [("Test.esm", locationFile)])
        let alias = QuestFixture.alias(
            id: 0,
            name: "Place",
            location: true,
            fill: QuestFixture.word("ALFL", 0x0500)
        )
        let questRecord = QuestFixture.record(
            formID: 0x0100,
            fields: QuestFixture.editorID("LocationQuest") + alias
        )
        let quests = try QuestRuntime(
            store: WorldStateStore(),
            quests: QuestFixture.store(questRecord),
            locations: locations
        )

        try quests.startQuest(FormID(0x0100))

        let table = try quests.aliasState(of: FormID(0x0100))
        let expected = ResolvedFormID(plugin: "Test.esm", objectID: 0x0500)
        #expect(table.location(forAlias: 0) == expected)
        #expect(table.reference(forAlias: 0) == nil)
        #expect(quests.aliasLocation(alias: 0, in: FormID(0x0100)) == expected)
    }
}

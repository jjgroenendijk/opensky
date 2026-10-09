// Direct ALFL and ALFA + ALRT quest-alias integration over synthetic records only.

import EngineTesting
import FormatsTesting
import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyQuests
@testable import OpenSkyQuestsInterface
@testable import OpenSkyWorldState
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

    @Test func aLocationAliasReferenceTakesTheNextFreeReferenceOfItsType() throws {
        let special = ESMFixture.words([
            0x600,
            0x700,
            0x3C,
            0,
            0x600,
            0x701,
            0x3C,
            0,
            0x601,
            0x702,
            0x3C,
            0
        ])
        let locationRecord = ESMFixture.record(
            "LCTN",
            formID: 0x0500,
            data: ESMFixture.field("EDID", ESMFixture.zstring("Town"))
                + ESMFixture.field("LCSR", special)
        )
        let locations = try LocationStore(plugins: [("Test.esm", ESMFile(
            data: ESMFixture.tes4() + ESMFixture.topGroup("LCTN", contents: locationRecord)
        ))])
        let inTown = { (id: UInt32, type: UInt32) in
            QuestFixture.alias(
                id: id, name: "Ref\(id)",
                fill: QuestFixture.word("ALFA", 3) + QuestFixture.word("ALRT", type)
            )
        }
        let fields = QuestFixture.editorID("TownQuest")
            + QuestFixture.alias(
                id: 3,
                name: "Town",
                location: true,
                fill: QuestFixture.word("ALFL", 0x0500)
            )
            + inTown(1, 0x600) + inTown(2, 0x600) + inTown(4, 0x601)
        let quests = try QuestRuntime(
            store: WorldStateStore(),
            quests: QuestFixture.store(QuestFixture.record(formID: 0x0100, fields: fields)),
            locations: locations
        )

        try quests.startQuest(FormID(0x0100))

        let table = try quests.aliasState(of: FormID(0x0100))
        let key = { ReferenceKey(resolved: ResolvedFormID(plugin: "Test.esm", objectID: $0)) }
        #expect(table.reference(forAlias: 1) == key(0x700))
        #expect(table.reference(forAlias: 2) == key(0x701))
        #expect(table.reference(forAlias: 4) == key(0x702))
    }
}

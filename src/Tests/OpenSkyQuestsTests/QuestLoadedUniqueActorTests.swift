// A unique-actor alias whose base has no persistent reference
// (docs/engine/quest-state.md).

import Foundation
import OpenSkyConditions
import OpenSkyEngineTesting
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
@testable import OpenSkyQuests
@testable import OpenSkyQuestsInterface
@testable import OpenSkyWorldState
import Testing

@MainActor
struct QuestLoadedUniqueActorTests {
    private let quest = FormID(0x0100)

    private func key(_ objectID: UInt32) -> ReferenceKey {
        .plugin(name: "test.esm", objectID: objectID)
    }

    private func actor(_ formID: UInt32, base: UInt32) throws -> RuntimeReferenceEntry {
        var name = Data()
        name.appendUInt32(base)
        let fields = ESMFixture.field("NAME", name) + ESMFixture.field("DATA", Data(count: 24))
        let record = try PlacedActor(
            record: ESMFixture.parseRecord(ESMFixture.record("ACHR", formID: formID, data: fields))
        )
        return RuntimeReferenceEntry(
            key: key(formID), formID: FormID(formID), isPersistent: false, record: .actor(record)
        )
    }

    /// A unique actor placed as a temporary reference is found among the loaded actors.
    @Test func aUniqueActorWithNoPersistentReferenceTakesItsLoadedActor() throws {
        let world = try QuestReferenceSearch(
            references: RuntimeReferenceIndex(entries: [
                actor(0x1000, base: 0x700), actor(0x1001, base: 0x701),
                actor(0x1002, base: 0x701)
            ]),
            origin: nil, context: ConditionContext()
        )
        #expect(world.loadedActor(ofBase: key(0x700)) == key(0x1000))
        #expect(world.loadedActor(ofBase: key(0x701)) == nil, "two actors give no answer")
        #expect(world.loadedActor(ofBase: key(0x702)) == nil)
        #expect(world.loadedActor(ofBase: .player) == nil)

        var runtime = try QuestRuntime(
            store: WorldStateStore(),
            quests: QuestFixture.store(QuestFixture.record(
                formID: 0x0100,
                fields: QuestFixture.editorID("MatchQuest") + QuestFixture.marker("ANAM")
                    + QuestFixture.alias(
                        id: 0,
                        name: "Seller",
                        fill: QuestFixture.word("ALUA", 0x700)
                    )
            )),
            locations: LocationStore(plugins: [])
        )
        runtime.referenceSearch = { world }
        try runtime.startQuest(quest)
        #expect(try runtime.aliasState(of: quest).reference(forAlias: 0) == key(0x1000))
    }
}

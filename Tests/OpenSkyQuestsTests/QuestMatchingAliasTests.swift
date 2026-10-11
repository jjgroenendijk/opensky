// The Find Matching Reference fill over synthetic loaded references: match
// conditions on each candidate, "Closest", "In Loaded Area", and the near-alias
// linked children.

import Foundation
import OpenSkyConditions
import OpenSkyEngineTesting
import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
@testable import OpenSkyQuests
@testable import OpenSkyQuestsInterface
@testable import OpenSkyWorldState
import Testing

@MainActor
@Suite("Quest matching aliases")
struct QuestMatchingAliasTests {
    private let quest = FormID(0x0100)
    private let chairBase: UInt32 = 0x0900
    private let tableBase: UInt32 = 0x0901

    private func key(_ objectID: UInt32) -> ReferenceKey {
        .plugin(name: "test.esm", objectID: objectID)
    }

    /// A REFR of `base` at `x`, linked to `link` when given.
    private func reference(_ formID: UInt32, base: UInt32, x: Float, link: UInt32? = nil) throws
        -> RuntimeReferenceEntry
    {
        var name = Data()
        name.appendUInt32(base)
        var place = Data()
        place.appendUInt32(x.bitPattern)
        place.append(Data(count: 20))
        var fields = ESMFixture.field("NAME", name) + ESMFixture.field("DATA", place)
        if let link {
            var linked = Data()
            linked.appendUInt32(link)
            fields += ESMFixture.field("XLKR", linked)
        }
        let record = try PlacedReference(
            record: ESMFixture.parseRecord(ESMFixture.record("REFR", formID: formID, data: fields))
        )
        return RuntimeReferenceEntry(
            key: key(formID), formID: FormID(formID), isPersistent: false,
            record: .reference(record)
        )
    }

    private func search(_ entries: [RuntimeReferenceEntry]) -> QuestReferenceSearch {
        var registry = ConditionFunctionRegistry()
        ConditionFunctions.installCore(into: &registry)
        let references = RuntimeReferenceIndex(entries: entries)
        var context = ConditionContext()
        context.references = references
        return QuestReferenceSearch(
            references: references,
            origin: SIMD3(0, 0, 0),
            context: context,
            registry: registry
        )
    }

    private func isID(_ base: UInt32) -> Data {
        DialogueFixture.condition(functionIndex: 72, comparisonValue: 1, parameter1: base)
    }

    private func runtime(aliases: Data, search: QuestReferenceSearch) throws -> QuestRuntime {
        var runtime = try QuestRuntime(
            store: WorldStateStore(),
            quests: QuestFixture.store(QuestFixture.record(
                formID: 0x0100,
                fields: QuestFixture.editorID("MatchQuest") + QuestFixture.marker("ANAM")
                    + aliases
            ))
        )
        runtime.referenceSearch = { search }
        return runtime
    }

    @Test func theClosestMatchingReferenceFillsTheAlias() throws {
        let world = try search([
            reference(0x1000, base: chairBase, x: 500),
            reference(0x1001, base: chairBase, x: 100),
            reference(0x1002, base: tableBase, x: 10)
        ])
        let alias = QuestFixture.alias(
            id: 0, name: "Chair", flags: 0x2020, extras: isID(chairBase)
        )
        let quests = try runtime(aliases: alias, search: world)
        try quests.startQuest(quest)
        #expect(try quests.aliasState(of: quest).reference(forAlias: 0) == key(0x1001))
    }

    /// In the loaded area, no match is a real miss, and a required alias refuses the start.
    @Test func noMatchInTheLoadedAreaRefusesTheStart() throws {
        let world = try search([reference(0x1002, base: tableBase, x: 10)])
        let alias = QuestFixture.alias(id: 0, name: "Chair", flags: 0x20, extras: isID(chairBase))
        let quests = try runtime(aliases: alias, search: world)
        #expect(throws: QuestError.self) { try quests.startQuest(quest) }
    }

    /// Outside "In Loaded Area" the reference may be unloaded, so a miss never refuses.
    @Test func noMatchAnywhereElseStillStarts() throws {
        let world = try search([reference(0x1002, base: tableBase, x: 10)])
        let alias = QuestFixture.alias(id: 0, name: "Chair", extras: isID(chairBase))
        let quests = try runtime(aliases: alias, search: world)
        try quests.startQuest(quest)
        #expect(try quests.aliasState(of: quest).reference(forAlias: 0) == nil)
    }

    @Test func aNearAliasTakesALinkedChildOfTheOtherAlias() throws {
        let world = try search([
            reference(0x1000, base: tableBase, x: 0),
            reference(0x1001, base: chairBase, x: 50, link: 0x1000),
            reference(0x1002, base: chairBase, x: 10)
        ])
        let table = QuestFixture.alias(
            id: 0, name: "Table", fill: QuestFixture.word("ALFR", 0x1000)
        )
        let chair = QuestFixture.alias(
            id: 1, name: "Chair",
            fill: QuestFixture.signedWord("ALNA", 0) + QuestFixture.word("ALNT", 0),
            extras: isID(chairBase)
        )
        let quests = try runtime(aliases: table + chair, search: world)
        try quests.startQuest(quest)
        #expect(try quests.aliasState(of: quest).reference(forAlias: 1) == key(0x1001))
    }
}

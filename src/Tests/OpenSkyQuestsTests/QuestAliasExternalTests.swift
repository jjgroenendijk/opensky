// The "External Alias" fill (ALEQ and ALEA) over synthetic `QuestFixture` bytes: an alias
// takes what another running quest's alias holds when this quest starts.

import Foundation
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
@Suite("Quest external alias")
struct QuestAliasExternalTests {
    private let source = FormID(0x0100)
    private let attack = FormID(0x0200)
    private let fromEmpty = FormID(0x0300)
    private let dragon = ReferenceKey.plugin(name: "test.esm", objectID: 0x0500)

    /// MQ101 holds the dragon in alias 0 and leaves alias 1 for a script. The attack takes
    /// alias 0 from it; the third quest asks for the empty alias 1.
    private func runtime() throws -> QuestRuntime {
        let quests = try QuestFixture.store(
            QuestFixture.record(
                formID: 0x0100,
                fields: QuestFixture.editorID("MQ101") + QuestFixture.general(type: 1)
                    + QuestFixture.alias(
                        id: 0,
                        name: "Alduin",
                        fill: QuestFixture.word("ALFR", 0x0500)
                    )
                    + QuestFixture.alias(id: 1, name: "Scripted", flags: 0x02)
            )
                + QuestFixture.record(
                    formID: 0x0200,
                    fields: QuestFixture.editorID("MQ101DragonAttack")
                        + QuestFixture.general(type: 1)
                        + QuestFixture.alias(id: 3, name: "Alduin", fill: external(alias: 0))
                )
                + QuestFixture.record(
                    formID: 0x0300,
                    fields: QuestFixture.editorID("NeedsTheScripted")
                        + QuestFixture.general(type: 1)
                        + QuestFixture.alias(id: 0, name: "Scripted", fill: external(alias: 1))
                )
        )
        return QuestRuntime(store: WorldStateStore(), quests: quests)
    }

    private func external(alias: UInt32) -> Data {
        QuestFixture.word("ALEQ", 0x0100) + QuestFixture.word("ALEA", alias)
    }

    @Test func theAliasTakesWhatTheRunningQuestsAliasHolds() throws {
        let quests = try runtime()
        try quests.startQuest(source)
        try quests.startQuest(attack)
        #expect(quests.aliasReference(alias: 3, in: attack) == dragon)
    }

    @Test func aStoppedSourceQuestFailsTheRequiredAlias() throws {
        let quests = try runtime()
        #expect(throws: QuestError.aliasFillFailed(quest: attack, aliases: [3])) {
            try quests.startQuest(attack)
        }
        #expect(quests.aliasReference(alias: 3, in: attack) == nil)
    }

    @Test func anEmptySourceAliasFailsTheRequiredAlias() throws {
        let quests = try runtime()
        try quests.startQuest(source)
        #expect(throws: QuestError.aliasFillFailed(quest: fromEmpty, aliases: [0])) {
            try quests.startQuest(fromEmpty)
        }
    }

    @Test func aLocationAliasTakesTheOtherQuestsLocation() throws {
        let quests = try runtime()
        let place = ResolvedFormID(plugin: "test.esm", objectID: 0x0800)
        let record = try QuestFixture.quest(
            formID: 0x0400,
            fields: QuestFixture.editorID("TakesThePlace")
                + QuestFixture.alias(id: 0, name: "Place", location: true, fill: external(alias: 2))
        )
        let running = [
            ReferenceKey.plugin(name: "test.esm", objectID: 0x0100):
                QuestAliasState().fillingLocation(2, with: place)
        ]
        let filled = QuestAliasFiller.fill(
            record, resolver: quests.quests.resolver, running: running
        )
        #expect(filled.state.location(forAlias: 0) == place)
        let missed = QuestAliasFiller.fill(record, resolver: quests.quests.resolver)
        #expect(missed.unfilledRequired == [0])
    }
}

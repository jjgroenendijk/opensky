// An alias that names the player fills with the player identity, the key
// `Game.GetPlayer()` returns, not with a plugin reference.

import EngineTesting
import FormatsTesting
import Foundation
import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyQuests
import OpenSkyQuestsInterface
import Testing

@Suite("Quest aliases that name the player")
struct QuestPlayerAliasTests {
    private let skyrim = FormIDResolver(pluginName: "Skyrim.esm", masters: [])

    private func quest(_ aliases: Data) throws -> Quest {
        let store = try QuestFixture.store(QuestFixture.record(
            formID: 0x0100,
            fields: QuestFixture.editorID("MQ101") + QuestFixture.marker("ANAM") + aliases
        ))
        return try #require(store.quest(FormID(0x0100)))
    }

    private func alias(_ id: UInt32, _ subrecord: String, _ form: UInt32) -> Data {
        QuestFixture.alias(id: id, name: "Player\(id)", fill: QuestFixture.word(subrecord, form))
    }

    @Test func aForcedPlayerReferenceFillsWithThePlayer() throws {
        let result = try QuestAliasFiller.fill(quest(alias(119, "ALFR", 0x14)), resolver: skyrim)

        #expect(result.state.reference(forAlias: 119) == .player)
        #expect(result.canStartQuest)
    }

    @Test func aUniqueActorAliasForThePlayerBaseFillsWithThePlayer() throws {
        let result = try QuestAliasFiller.fill(quest(alias(3, "ALUA", 0x07)), resolver: skyrim)

        #expect(result.state.reference(forAlias: 3) == .player)
        #expect(result.skipped.total == 0)
    }

    /// Only `Skyrim.esm` defines the player, so a plugin's own object 0x14 is
    /// an ordinary reference.
    @Test func objectFourteenOfAnotherPluginStaysAPluginReference() throws {
        let other = FormIDResolver(pluginName: "Other.esp", masters: ["Skyrim.esm"])
        let result = try QuestAliasFiller.fill(
            quest(alias(0, "ALFR", 0x0100_0014) + alias(1, "ALFR", 0x14)),
            resolver: other
        )

        #expect(result.state.reference(forAlias: 0) == .plugin(name: "other.esp", objectID: 0x14))
        #expect(result.state.reference(forAlias: 1) == .player)
    }

    @Test func anotherUniqueActorIsStillACountedSkip() throws {
        let result = try QuestAliasFiller.fill(quest(alias(0, "ALUA", 0x0700)), resolver: skyrim)

        #expect(result.state.isEmpty)
        #expect(result.skipped.counts[.unsupportedFillType(.uniqueActor)] == 1)
    }
}

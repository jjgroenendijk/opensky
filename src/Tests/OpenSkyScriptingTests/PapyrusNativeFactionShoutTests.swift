// Faction reactions and shout knowledge that scripts set, over a synthetic lever. The
// lever and the door stand in for factions, words, and shouts, as the natives only need
// two forms.

import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
import OpenSkyQuestsInterface
@testable import OpenSkyScripting
import OpenSkyScriptingFixtures
@testable import OpenSkyScriptingInterface
import Testing

@MainActor
struct PapyrusNativeFactionShoutTests {
    private typealias Fixture = PapyrusNativeReferenceFixture

    private func call(
        _ fixture: Fixture, _ script: String, _ name: String,
        _ arguments: [PapyrusValue] = [], returnType: PapyrusType = .none
    ) -> PapyrusNativeResult {
        fixture.registry.invoke(PapyrusWorldFixture.methodCall(
            script, name, receiver: fixture.receiver, arguments: arguments,
            returnType: returnType
        ))
    }

    @Test func setEnemyAndSetAllyStoreBothDirections() throws {
        let fixture = try Fixture.make()
        var published: [FactionReactionOverride] = []
        fixture.session.bridge.natives.faction.reactionsChanged = { published = $0 }
        let door = Fixture.key(Fixture.doorID)
        let other = fixture.handle(Fixture.doorID)

        #expect(call(fixture, "Faction", "SetEnemy", [.object(other), .boolean(true)])
            == .returned(.none))
        #expect(Set(published.map { "\($0.from)>\($0.toward)=\($0.reaction)" }) == [
            "\(fixture.key)>\(door)=neutral", "\(door)>\(fixture.key)=enemy"
        ])
        _ = call(fixture, "Faction", "SetAlly", [.object(other)])
        #expect(published.allSatisfy { $0.reaction == .ally })
        #expect(published.count == 2)
    }

    @Test func setReactionSetsOneSideFromItsCombatReactionCode() throws {
        let fixture = try Fixture.make()
        let door = Fixture.key(Fixture.doorID)
        let other = PapyrusValue.object(fixture.handle(Fixture.doorID))
        #expect(call(fixture, "Faction", "SetReaction", [other, .integer(3)])
            == .returned(.none))
        #expect(fixture.session.bridge.scriptState.scriptedFactionReactions().map {
            "\($0.from)>\($0.toward)=\($0.reaction)"
        } == ["\(fixture.key)>\(door)=friend"])
        #expect(PapyrusWorldFixture.isInvalidArguments(
            call(fixture, "Faction", "SetReaction", [other, .integer(-50)])
        ))
    }

    @Test func setPlayerEnemyPairsWithThePlayerFaction() throws {
        let fixture = try Fixture.make()
        _ = call(fixture, "Faction", "SetPlayerEnemy")
        let reactions = fixture.session.bridge.scriptState.scriptedFactionReactions()
        #expect(reactions.contains {
            $0.from == PapyrusNativeFunctions.FactionRelationsNatives.playerFaction && $0
                .reaction == .enemy
        })
        _ = call(fixture, "Faction", "SetPlayerEnemy", [.boolean(false)])
        #expect(fixture.session.bridge.scriptState.scriptedFactionReactions().allSatisfy {
            $0.reaction == .neutral
        })
    }

    @Test func wordsAndShoutsAreRemembered() throws {
        let fixture = try Fixture.make()
        let word = fixture.handle(Fixture.doorID)
        #expect(call(fixture, "Game", "IsWordUnlocked", [.object(word)], returnType: .boolean)
            == .returned(.boolean(false)))
        _ = call(fixture, "Game", "TeachWord", [.object(word)])
        #expect(call(fixture, "Game", "IsWordUnlocked", [.object(word)], returnType: .boolean)
            == .returned(.boolean(false)))
        _ = call(fixture, "Game", "UnlockWord", [.object(word)])
        _ = call(fixture, "Game", "UnlockWord", [.object(word)])
        #expect(call(fixture, "Game", "IsWordUnlocked", [.object(word)], returnType: .boolean)
            == .returned(.boolean(true)))
        let stats = fixture.session.worldState.miscStats
        #expect(stats.values == ["Words Of Power Learned": 1, "Words Of Power Unlocked": 1])

        _ = call(fixture, "Actor", "AddShout", [.object(word)])
        _ = call(fixture, "Actor", "EquipShout", [.object(word)])
        #expect(call(fixture, "Actor", "GetEquippedShout", returnType: .object("Shout"))
            == .returned(.object(word)))
        #expect(call(fixture, "Actor", "RemoveShout", [.object(word)], returnType: .boolean)
            == .returned(.boolean(true)))
        #expect(call(fixture, "Actor", "GetEquippedShout", returnType: .object("Shout"))
            == .returned(.none))
        #expect(call(fixture, "Actor", "RemoveShout", [.object(word)], returnType: .boolean)
            == .returned(.boolean(false)))
    }

    /// docs/engine/statistics.md, Shouts: the stats a one-word shout's word raises.
    @Test func teachingAndUnlockingAShoutsOnlyWordCountsTheShout() throws {
        let fixture = try Fixture.make()
        let menus = FakeMenuBridge()
        let word = Fixture.key(Fixture.doorID)
        menus.wordSlots = [Fixture.key(Fixture.leverID): [word, nil, nil]]
        fixture.session.bridge.ports.menus = menus
        _ = call(fixture, "Game", "TeachWord", [.object(fixture.handle(Fixture.doorID))])
        _ = call(fixture, "Game", "UnlockWord", [.object(fixture.handle(Fixture.doorID))])
        #expect(fixture.session.worldState.miscStats.values == [
            "Words Of Power Learned": 1, "Shouts Learned": 1,
            "Words Of Power Unlocked": 1, "Shouts Unlocked": 1, "Shouts Mastered": 1
        ])
    }
}

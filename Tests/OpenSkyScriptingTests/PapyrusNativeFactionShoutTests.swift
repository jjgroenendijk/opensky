// Faction reactions and shout knowledge that scripts set, over a synthetic lever. The
// lever and the door stand in for factions, words, and shouts, as the natives only need
// two forms.

import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyScripting
import OpenSkyScriptingFixtures
@testable import OpenSkyScriptingInterface
@testable import OpenSkyWorldState
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
        fixture.session.bridge.factionReactionsChanged = { published = $0 }
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

    @Test func setPlayerEnemyPairsWithThePlayerFaction() throws {
        let fixture = try Fixture.make()
        _ = call(fixture, "Faction", "SetPlayerEnemy")
        let reactions = fixture.session.bridge.scriptedFactionReactions()
        #expect(reactions.contains {
            $0.from == PapyrusNativeFunctions.playerFaction && $0.reaction == .enemy
        })
        _ = call(fixture, "Faction", "SetPlayerEnemy", [.boolean(false)])
        #expect(fixture.session.bridge.scriptedFactionReactions().allSatisfy {
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
        #expect(call(fixture, "Game", "IsWordUnlocked", [.object(word)], returnType: .boolean)
            == .returned(.boolean(true)))

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
}

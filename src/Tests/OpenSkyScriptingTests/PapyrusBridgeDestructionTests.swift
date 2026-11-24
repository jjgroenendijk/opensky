// The script bridge forwards destruction damage and its pending stage changes, and sets
// a scripted owner the way SetActorOwner and SetFactionOwner do.

import OpenSkyCrimeInterface
import OpenSkyFormatsESM
@testable import OpenSkyScripting
import OpenSkyScriptingInterface
import OpenSkyWorldState
import Testing

@MainActor
struct PapyrusBridgeDestructionTests {
    private let bridge = PapyrusWorldStateBridge(worldState: WorldStateStore())
    private static let barrel = ReferenceKey.generated(30)
    private static let owner = ReferenceKey.plugin(name: "base.esm", objectID: 0x40)

    @Test func anObjectWithoutDestructionDataTakesNoDamage() {
        #expect(!bridge.damageDestructible(Self.barrel, amount: 10, forced: false))
        #expect(bridge.destructionHealthLeft(of: Self.barrel) == nil)
        #expect(bridge.takeDestructionChanges().isEmpty)
    }

    @Test func aScriptedOwnerIsAnActorOrAFaction() {
        bridge.setScriptedOwner(.actor(Self.owner), of: Self.barrel)
        var state = bridge.scriptedState(of: Self.barrel)
        #expect(state.flag(PapyrusWorldStateBridge.ownerSetName) == true)
        #expect(state.form("actorOwner") == Self.owner)
        bridge.setScriptedOwner(.faction(Self.owner, requiredRank: 0), of: Self.barrel)
        state = bridge.scriptedState(of: Self.barrel)
        #expect(state.form("actorOwner") == nil)
        #expect(state.form("factionOwner") == Self.owner)
    }
}

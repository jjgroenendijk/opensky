// The members the session reaches the bridge through, over a session with no
// feature runtimes: each answers its empty value instead of failing.

import Foundation
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyScripting
import OpenSkyScriptingFixtures
import OpenSkyScriptingInterface
@testable import OpenSkyWorldState
import Testing

@MainActor
struct PapyrusWorldStateBridgePortTests {
    @Test func theRoleBridgesAnswerWithoutRuntimes() throws {
        let fixture = try PapyrusNativeReferenceFixture.make()
        let bridge = fixture.session.bridge
        let key = fixture.key
        #expect(bridge.magicBridge.spellState(for: key) == nil)
        #expect(bridge.crimeBridge.crimeGold(of: key) == nil)
        #expect(bridge.factionBridge.isInFaction(key, faction: key) == nil)
        #expect(bridge.guardBridge.isGuard(key) == nil)
        #expect(bridge.isInFaction(key, faction: key) == nil)
        #expect(bridge.isHostile(key, toward: .player) == nil)
        _ = bridge.relationshipRank(of: key, toward: .player)
        #expect(Result { try bridge.stopQuest(for: key) }.isFailure)
        #expect(Result { try bridge.setQuestStage(1, for: key) }.isFailure)
    }

    @Test func theActorAndSpellMembersRefuseWithoutRuntimes() throws {
        let fixture = try PapyrusNativeReferenceFixture.make()
        let bridge = fixture.session.bridge
        let key = fixture.key
        #expect(!bridge.startActorCombat(key, target: .player))
        #expect(!bridge.stopActorCombat(key))
        #expect(!bridge.killActor(key, killer: nil))
        #expect(!bridge.resurrectActor(key))
        #expect(!bridge.addSpell(key, to: key))
        #expect(!bridge.removeSpell(key, from: key))
        #expect(!bridge.castSpell(key, from: key, at: nil, blame: nil))
        _ = bridge.actorFlags(of: key, record: nil)
        #expect(bridge.silentDeath == nil)
    }

    @Test func thePlacementAndScriptStateMembersReadTheReference() throws {
        let fixture = try PapyrusNativeReferenceFixture.make()
        let bridge = fixture.session.bridge
        let key = fixture.key
        #expect(bridge.placement(of: key) != nil)
        _ = bridge.spawnReference(of: key, at: key)
        if let location = bridge.cellLocation(of: key) {
            bridge.relocate(key, to: location)
        }
        bridge.queueItemRead(base: key)
        bridge.updateScriptedState(of: key) { $0.setFlag(ScriptedStateName.eaten, true) }
        #expect(bridge.scriptedState(of: key).flag(ScriptedStateName.eaten) == true)
        _ = bridge.scriptedStateResolution()
        bridge.publishFactionReactions()
        bridge.publishLeveledEdits()
        bridge.recordKill(victim: key, killer: .player)
        bridge.markLocationCleared(key, playsMusic: false)
        bridge.recordHit(ScriptHitEvent(target: key, aggressor: .player), targetWasHostile: false)
        #expect(!bridge.isPlayerSunGazing)
        _ = bridge.playerControlLocks
        bridge.noteStolenValue(10, from: key, witnessed: false)
    }

    @Test func theScriptEventMembersQueueNothingWithoutQuests() throws {
        let fixture = try PapyrusNativeReferenceFixture.make()
        let bridge = fixture.session.bridge
        #expect(bridge.attachRunningQuestScripts() == 0)
        #expect(bridge.attachScripts(ofQuest: FormID(0x10)) == 0)
        _ = bridge.queuePackageEvent(slot: 0x01, package: FormID(0x11), actor: fixture.key)
        #expect(bridge.queueStoryStartEvent(
            quest: FormID(0x12), event: StoryEventData(event: "KILL")
        ) == 0)
        let package = try PackageDecoder.decode(PackageFixture.record(
            fields: PackageFixture.general(kind: 0, speed: 0) + PackageFixture.schedule()
        ))
        #expect(!bridge.runPackageFragment(of: package, slot: 0x01, actor: fixture.key))
        #expect(bridge.dialogueFragments === bridge.fragments)
        #expect(bridge.sceneFragments === bridge.fragments)
    }
}

extension Result {
    fileprivate var isFailure: Bool {
        if case .failure = self {
            return true
        }
        return false
    }
}

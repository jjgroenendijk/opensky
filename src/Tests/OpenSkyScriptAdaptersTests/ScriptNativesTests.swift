// Each native the Script adapters fill reaches the session port that owns its answer.

import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPerceptionInterface
import OpenSkyRuntimeState
@testable import OpenSkyScriptAdapters
import OpenSkyScripting
import OpenSkyScriptingInterface
import OpenSkySessionTesting
import OpenSkyWorldState
import Testing

@MainActor
struct ScriptNativesTests {
    private let host = ScriptHost()
    private let bridge = PapyrusWorldStateBridge(worldState: WorldStateStore())
    private var adapter: ScriptWorldAdapter {
        ScriptWorldAdapter(game: host, stage: nil)
    }

    private static let actor = ReferenceKey.generated(3)

    @Test func actorNativesAnswerFromTheirPorts() {
        host.fakeRuntimeStateWorld.conditionDataResult = .empty
        host.fakePerception.perceptionResolutionResult = .empty
        host.fakeAIWorld.lightLevelResult = 0.25
        host.fakePackages.templateResult = FormID(0x50)
        adapter.actorBindings.fillActorNatives(bridge: bridge)
        let natives = bridge.actorNatives
        #expect(natives.actorValueRuntime?() == nil)
        #expect(natives.ragdollRuntime?() == nil)
        #expect(natives.combatRuntime?() == nil)
        #expect(natives.weaponDrawState?(Self.actor) == nil)
        #expect(natives.weaponDrawState?(.player) == nil)
        _ = bridge.sessionNatives.conditionData?()
        _ = bridge.perceptionNatives.detection?()
        #expect(bridge.sessionNatives.currentPackage?(Self.actor) == nil)
        #expect(bridge.sessionNatives.packageTemplate?(FormID(0x40)) == FormID(0x50))
        #expect(bridge.perceptionNatives.lightLevel?(.zero) == 0.25)
        #expect(bridge.perceptionNatives.livePosition?(.player) == nil)
        #expect(bridge.perceptionNatives.livePosition?(Self.actor) == nil)
        #expect(host.fakeRuntimeStateWorld.conditionDataCallCount == 1)
        #expect(host.fakePerception.perceptionResolutionCallCount == 1)
        #expect(host.fakeActorWorld.combatActorCalls == [Self.actor])
    }

    @Test func perkNativesChangePerksAndSkills() {
        host.fakeFactionWorld.papyrusNativesResult = PapyrusFactionNatives()
        host.fakeActorWorld.actorValueHolderResult = .player
        host.fakePerks.addResult = true
        host.fakeProgression.incrementSkillResult = true
        host.fakeProgression.modifyPerkPointsResult = 2
        adapter.perkBindings.fillPerkNatives(bridge: bridge)
        let natives = bridge.progressionNatives
        #expect(natives.mutatePerks?(.add, Self.actor, .player) == true)
        #expect(natives.mutatePerks?(.remove, Self.actor, .player) == false)
        #expect(natives.perkOwnership?(Self.actor) == nil)
        #expect(natives.advanceSkill?(.increment, 10, 1) == true)
        #expect(natives.modifyPerkPoints?(0) == 2)
        #expect(bridge.crimeNatives.crimeReporter?() == nil)
        #expect(bridge.crimeNatives.showBarterMenu?(Self.actor) == nil)
        #expect(host.fakePerks.addCalls.count == 1)
        #expect(host.fakePerks.removeCalls.count == 1)
        #expect(host.fakeProgression.incrementSkillCalls == [10])
    }

    @Test func playerNativesReachMountSneakAndHUD() {
        host.fakeMountWorld.dismountResult = true
        adapter.fillPlayerNatives(bridge: bridge)
        #expect(bridge.sessionNatives.leveledEdits?() == nil)
        #expect(bridge.playerNatives.dismount?(.player) == true)
        bridge.playerNatives.togglePlayerSneaking?()
        bridge.playerNatives.toggleMenus?()
        _ = bridge.playerNatives.playersLastMount?()
        #expect(host.fakePlayer.isSneaking)
        #expect(host.fakeMountWorld.dismountCalls == [.player])
    }

    @Test func skyNativesNeedASession() {
        adapter.skyBindings.fillSky(bridge: bridge)
        #expect(bridge.sessionNatives.towardSun?() == nil)
        #expect(bridge.sessionNatives.playerView?() == nil)
        #expect(bridge.sessionNatives.skyMode?() == ScriptSkyBindingsAdapter.SkyMode.full)
        host.fakeStreamer.isInterior = true
        #expect(bridge.sessionNatives.skyMode?() == ScriptSkyBindingsAdapter.SkyMode.interior)
    }

    @Test func anActorSeesThroughPerception() {
        host.fakePerception.perceptionResolutionResult = .empty
        adapter.nodeBindings.fillLineOfSight(bridge: bridge)
        #expect(bridge.perceptionNatives.seesTarget?(Self.actor, .player) == nil)
        #expect(bridge.perceptionNatives.seesTarget?(.player, Self.actor) == nil)
    }
}

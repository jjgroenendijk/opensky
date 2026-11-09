// The game natives reach saves, menus, effects, sounds, paths, and references.

import OpenSkyFormatsESM
@testable import OpenSkyScriptAdapters
import OpenSkyScripting
import OpenSkyScriptingInterface
import OpenSkySessionTesting
import OpenSkyWorldState
import Testing

@MainActor
struct ScriptGameNativesTests {
    private let host = ScriptHost()
    private let bridge = PapyrusWorldStateBridge(worldState: WorldStateStore())
    private var natives: PapyrusGameNatives {
        bridge.gameNatives
    }

    private static let actor = ReferenceKey.generated(3)

    init() {
        ScriptWorldAdapter(game: host).sessionBindings.fillGameNatives(bridge: bridge)
    }

    @Test func savesMenusAndEffectsReachTheirPorts() {
        host.fakeSaveGames.requestSaveResult = true
        #expect(natives.requestSave?(true) == true)
        natives.quitToMainMenu?()
        natives.quitGame?()
        natives.showTitleSequenceMenu?(true)
        natives.startTitleSequence?("Intro")
        natives.screenBlood?(3)
        natives.clearTempEffects?()
        natives.toggleCollisions?()
        natives.showFirstPersonGeometry?(true)
        #expect(natives.takeScreenshot?("Shot") == false)
        #expect(natives.centerOnCell?("WhiterunExterior01") == true)
        #expect(host.quitToMainMenuCallCount == 1)
        #expect(host.quitApplicationCallCount == 1)
        #expect(host.fakeTitleSequence.showCalls == [true])
        #expect(host.fakeEffects.splatterScreenCountCalls == [3])
        #expect(host.fakeEffects.clearTemporaryBloodCallCount == 1)
        #expect(host.fakeMenuWorld.teleportPlayerCalls.count == 1)
    }

    @Test func playerRulesReachCrimeMagicAndPackages() {
        natives.setGodMode?(true)
        natives.setFootIK?(false)
        natives.clearPrison?()
        natives.setPlayerReportsCrime?(true)
        #expect(natives.playerGrabbedReference?() == nil)
        #expect(natives.packageLocation?(Self.actor) == nil)
        #expect(natives.forceRagdoll?(Self.actor) == false)
        #expect(natives.setEyeTexture?(.player, Self.actor) == false)
        #expect(host.fakeCrime.clearPrisonCallCount == 1)
        #expect(host.fakeActorGraphs.footIk == false)
        #expect(host.fakePackages.packageLocationCalls == [Self.actor])
    }

    @Test func referenceRulesNeedTheirReference() {
        #expect(natives.clearExtraArrows?(Self.actor) == 0)
        #expect(natives.resetCell?(Self.actor) == false)
        #expect(host.fakeStreamer.referenceEntryKeyCalls == [Self.actor])
    }

    @Test func soundsAndPathsNeedTheirSession() {
        #expect(natives.playSound?(Self.actor, .player, 1) == 0)
        natives.stopSound?(1)
        natives.setSoundVolume?(1, 0.5)
        natives.setParticleGeometry?(nil, 1)
        #expect(natives.pathToReference?(Self.actor, .player, 1, 2) == false)
        host.fakeMovieWorld.playBinkResult = true
        #expect(host.fakeStreamer.moveActorCalls.isEmpty)
    }
}

import AVFoundation
import Foundation

// The audio world reads the mix and the listener; the runtime state world reads clocks and facts.

import OpenSkyActorsInterface
import OpenSkyAudio
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkySessionAdapters
import OpenSkySessionTesting
import OpenSkyWorldConditionFunctions
import OpenSkyWorldState
import Testing

@MainActor
struct AudioRuntimeStateTests {
    private let host = SessionHost()
    private static let speaker = ReferenceKey.plugin(name: "base.esm", objectID: 0x20)

    @Test func theMixFollowsMenusLoadingAndDialogue() {
        let audio = AudioWorldAdapter(game: host, stage: nil)
        host.fakeMenuMode.isWorldSimPaused = true
        host.fakeLoadingScreens.isCovering = true
        host.fakeDialogueMenu.isOpen = true
        let inputs = audio.mix.soundMixInputs()
        #expect(inputs.menuMode)
        #expect(inputs.loading)
        #expect(inputs.dialogue)
        #expect(!inputs.statsMenu)
    }

    @Test func onlyTheOpenSpeakerIsTheConversationSpeaker() {
        let audio = AudioWorldAdapter(game: host, stage: nil)
        host.fakeDialogueMenu.speakerOrTarget = Self.speaker
        #expect(!audio.mix.isConversationSpeaker(Self.speaker))
        host.fakeDialogueMenu.isOpen = true
        #expect(audio.mix.isConversationSpeaker(Self.speaker))
    }

    @Test func noConditionsAlwaysPassForThePlayer() {
        let audio = AudioWorldAdapter(game: host, stage: nil)
        host.fakeRuntimeState.conditionContextResult = ConditionContext()
        #expect(audio.mix.playerConditionsPass([]))
        #expect(host.fakeRuntimeState.conditionContextCalls.count == 1)
    }

    @Test func withoutASessionTheListenerStandsAtTheOrigin() {
        let audio = AudioWorldAdapter(game: host, stage: nil)
        host.fakeDialogueWorld.headPositionResult = .one
        #expect(audio.listener.audioListenerPose.position == .zero)
        #expect(audio.listener.audioListenerPose.yaw == 0)
        #expect(audio.listener.playerFeetArmatures == nil)
        #expect(audio.listener.playerGait == nil)
        #expect(audio.listener.playerFeetPosition == nil)
        #expect(audio.listener.audioAnimationTime == 0)
        #expect(audio.listener.lipSyncTarget() == nil)
        #expect(audio.listener.speakerHeadPosition(of: Self.speaker) == .one)
        #expect(audio.audioWorldData == nil)
        #expect(audio.audioFileSystem == nil)
    }

    @Test func withoutASessionTheClockReadsAreEmpty() {
        let world = RuntimeStateWorldAdapter(
            game: host,
            now: { Date(timeIntervalSinceReferenceDate: 0) }
        )
        let clock = world.sessionClock
        #expect(clock.referenceEntry(formID: FormID(0x40)) == nil)
        #expect(host.fakeStreamer.referenceEntryFormIDCalls == [FormID(0x40)])
        #expect(clock.crosshairReference == nil)
        #expect(clock.gameClock == nil)
        #expect(clock.timescale == nil)
        #expect(clock.projectTimeGlobal(.gameHour, value: 3) == nil)
        #expect(clock.musicStore == nil)
        #expect(clock.globalStore == nil)
        #expect(clock.playerPlace() == nil)
        clock.setTimeOfDay(5)
    }

    @Test func withoutActorValuesTheActorsAreEmpty() {
        let world = RuntimeStateWorldAdapter(
            game: host,
            now: { Date(timeIntervalSinceReferenceDate: 0) }
        )
        _ = world.actorResolution()
        #expect(host.fakeActorWorld.combatActorsCallCount == 0)
        let key = CellLocationKey(
            location: .interior(FormID(0x50)), locationLink: nil, ownerPluginName: nil,
            worldspace: nil
        )
        #expect(world.location(of: key) == nil)
        #expect(world.locationMusicType(of: key) == nil)
    }

    @Test func withoutAnInventoryTheInventoryFactsAreEmpty() {
        let world = RuntimeStateWorldAdapter(
            game: host,
            now: { Date(timeIntervalSinceReferenceDate: 0) }
        )
        #expect(world.inventoryFacts.inventoryResolution(context: ConditionContext()) == nil)
        #expect(world.inventoryFacts.playerIsOverEncumbered() == nil)
        var state = ActorConditionState(current: .zero, maximums: .zero)
        world.inventoryFacts.playerTraits.fill(&state)
        #expect(state.isSneaking == nil)
        #expect(state.isInDangerousWater == nil)
    }

    @Test func mountSeamsReadTheVehicleAndFlightPorts() {
        let world = RuntimeStateWorldAdapter(
            game: host,
            now: { Date(timeIntervalSinceReferenceDate: 0) }
        )
        var context = ConditionContext()
        world.referenceMotion.addMountSeams(to: &context)
        #expect(context.mounts.canFlyHere)
        #expect(context.mounts.crashLandRequests.isEmpty)
    }

    @Test func withoutSoundRecordsTheEngineKeepsItsMix() throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2))
        let engine = WorldAudioEngine(manualRenderingFormat: format)
        let audio = AudioWorldAdapter(game: host, stage: nil)
        audio.applySoundMix(to: engine)
        #expect(engine.soundMix == nil)
        #expect(audio.footstepStore == nil)
    }
}

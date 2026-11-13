// The scene cast, scene lines, and ambient talk parts time, delay, and voice each line.

import Foundation
import OpenSkyActorsInterface
import OpenSkyDialogue
import OpenSkyDialogueInterface
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyFormatsTesting
import OpenSkyPhysics
import OpenSkySessionTesting
import OpenSkyStoryAdapters
import OpenSkyWorldInterface
import Testing

@MainActor
struct StorySceneTalkTests {
    private let host = StoryHost()
    private let adapter: StoryWorldAdapter
    private static let speaker = ReferenceKey.plugin(name: "base.esm", objectID: 0x20)
    private static let owner = ScenePackageOwner(scene: FormID(0x80), action: 1)

    init() {
        adapter = StoryWorldAdapter(
            game: host,
            stage: nil,
            now: { Date(timeIntervalSinceReferenceDate: 0) }
        )
        host.fakeDialogue.speechTimersValue = SpeechTimerSettings()
        host.fakeScenes.catalogValue = .empty
        host.fakeStreamer.dynamicBodiesValue = DynamicBodyWorld()
    }

    @Test func scenePackagesRunAsOverrides() {
        host.fakePackages.runOverrideResult = .done
        #expect(adapter
            .runScenePackages([FormID(0x90)], actor: Self.speaker, owner: Self.owner) == .done)
        host.fakePackages.runOverrideResult = .running
        #expect(adapter.runScenePackages([], actor: Self.speaker, owner: Self.owner) == .running)
        adapter.releaseScenePackages(actor: Self.speaker, owner: Self.owner)
        #expect(host.fakePackages.runOverrideCalls.map(\.override.packages) == [[FormID(0x90)], []])
        #expect(host.fakePackages.clearOverrideCalls.map(\.actor) == [Self.speaker])
    }

    @Test func theActorStatusReadsDeathAndConversation() {
        host.fakeWorldState.componentResult = ActorDeathState(isDead: true)
        host.fakeDialogue.conversationSpeaker = Self.speaker
        #expect(adapter.sceneActorStatus(Self.speaker) == [.dead, .inPlayerDialogue])
        #expect(adapter.sceneSeconds == 0)
        #expect(adapter.sceneFragments == nil)
        adapter.stopQuest(FormID(0x90))
    }

    @Test func anAbsentSpeakerHasAnInstantLine() throws {
        let info = try DialogueFixture.info(Data())
        #expect(adapter.lineDuration(of: info, speaker: Self.speaker) == 0)
        #expect(host.fakeStreamer.residents.residentActorEntryCalls == [Self.speaker])
        #expect(adapter.voicePaths(of: FormID(0x91), speaker: Self.speaker).isEmpty)
    }

    @Test func aDelayedLineWaitsForItsTime() {
        adapter.speak(info: FormID(0x91), speaker: Self.speaker, lookAt: nil, seconds: 2)
        #expect(adapter.state.delayedLines.map(\.info) == [FormID(0x91)])
        host.fakeDialogueWorld.headPositionResult = .zero
        adapter.ambientTalk.tickAmbientSpeech()
        #expect(host.fakeAudio.speakCalls.isEmpty)
        #expect(adapter.state.delayedLines.count == 1)
    }

    @Test func aLineWithoutDelayIsVoicedAndSubtitled() {
        host.fakeDialogue.speechTimersValue?.speechDelay = 0
        host.fakeDialogueWorld.headPositionResult = .zero
        adapter.sceneLines.run([
            .speak(SceneLine(
                speaker: Self.speaker,
                topic: FormID(0x92),
                info: FormID(0x91),
                lookAt: .player
            ))
        ])
        #expect(host.fakeAudio.speakCalls.map(\.paths) == [[]])
        #expect(host.fakeHeadTracking.setLookTargetCalls.count == 1)
        #expect(host.fakeSubtitles.sayCalls.count == 1)
    }

    @Test func aSpeakerWithoutAHeadSaysNothing() {
        host.fakeDialogue.speechTimersValue?.speechDelay = 0
        adapter.speak(info: FormID(0x91), speaker: Self.speaker, lookAt: nil, seconds: 1)
        #expect(host.fakeDialogueWorld.headPositionCalls == [Self.speaker])
        #expect(host.fakeAudio.speakCalls.isEmpty)
    }

    @Test func withoutADialogueRuntimeNoLineIsChosen() {
        adapter.say(FormID(0x91), speaker: Self.speaker)
        #expect(adapter.sayTopic("TRES", speaker: Self.speaker, lookAt: .player) == nil)
        adapter.sayOwnLine(.knockOver, speaker: Self.speaker)
        adapter.commentOnPlayer(.knockOver)
        #expect(host.fakeDialogue.npcLineCalls.count == 1)
        #expect(host.fakeDialogue.isSharedReadyCalls.count == 1)
        #expect(host.fakeAudio.speakCalls.isEmpty)
    }

    @Test func ambientSpeechWaitsForItsInterval() {
        for _ in 0 ..< StoryAmbientTalkAdapter.ambientSpeechInterval {
            adapter.ambientTalk.tickAmbientSpeech()
        }
        #expect(adapter.state.framesSinceAmbientSpeech == 0)
        #expect(adapter.state.lastAmbientSpeechSeconds == 0)
        #expect(host.fakeDialogue.ambientLinesCalls.isEmpty)
    }
}

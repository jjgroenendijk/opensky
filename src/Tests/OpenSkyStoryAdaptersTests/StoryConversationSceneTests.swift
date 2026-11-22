// The scene host parts that bring conversation partners together and say the
// detection lines.

import Foundation
import OpenSkyActorsInterface
import OpenSkyDialogue
import OpenSkyDialogueInterface
import OpenSkyFormatsESM
import OpenSkyPhysics
import OpenSkyScriptingInterface
import OpenSkySessionTesting
@testable import OpenSkyStoryAdapters
import OpenSkyWorldState
import Testing

@MainActor
struct StoryConversationSceneTests {
    private let host = StoryHost()
    private let adapter: StoryWorldAdapter
    private static let speaker = ReferenceKey.plugin(name: "base.esm", objectID: 0x20)
    private static let partner = ReferenceKey.plugin(name: "base.esm", objectID: 0x21)

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

    @Test func partnersMeetThroughTheSocialPass() {
        let social = host.fakeStoryManager.social
        social.meetForSceneResult = true
        #expect(adapter.conversationPartnersMeet(Self.speaker, Self.partner))
        #expect(social.meetForSceneCalls.map(\.partner) == [Self.partner])
    }

    /// The player is never turned, and a speaker without a head has nothing to face.
    @Test func aSpeakerWithoutAHeadCountsAsFacing() {
        #expect(adapter.sceneSpeakerFaces(.player, Self.partner))
        #expect(adapter.sceneSpeakerFaces(Self.speaker, Self.partner))
    }

    @Test func aStandingSpeakerTurnsToItsListener() {
        host.fakeDialogueWorld.headPositionResult = .zero
        host.fakeStreamer.actors.turnActorResult = 1
        #expect(!adapter.sceneSpeakerFaces(Self.speaker, Self.partner))
        host.fakeStreamer.actors.turnActorResult = 0.1
        #expect(adapter.sceneSpeakerFaces(Self.speaker, Self.partner))
    }

    /// With a session the ambient pass builds its frame and asks for detection lines.
    @Test func theAmbientPassReachesTheDetectionLines() {
        let session = FakeGameSessionPort()
        session.gameClockValue = GameClock()
        host.gameSession = session
        for _ in 0 ..< StoryAmbientTalkAdapter.ambientSpeechInterval {
            adapter.ambientTalk.tickAmbientSpeech()
        }
        #expect(host.fakeDialogue.ambientLinesCalls.count == 1)
        #expect(host.fakeDialogue.detectionLinesCalls.isEmpty, "no combat loop runs")
    }

    @Test func theSavedDeadAreTheActorsTheStoreMarksDead() {
        let store = WorldStateStore()
        store.set(ActorDeathState(isDead: true), for: Self.speaker)
        store.set(ActorDeathState(isDead: false), for: Self.partner)
        #expect(StoryWorldAdapter.savedDead(in: store) == [Self.speaker])
    }

    @Test func theAliasSearchKnowsADestroyedObject() {
        let store = WorldStateStore()
        var state = ScriptedReferenceState()
        state.setFlag(ScriptedStateName.destroyed, true)
        store.set(state, for: Self.speaker)
        #expect(StoryWorldAdapter.isDestroyed(Self.speaker, in: store))
        #expect(!StoryWorldAdapter.isDestroyed(Self.partner, in: store))
    }
}

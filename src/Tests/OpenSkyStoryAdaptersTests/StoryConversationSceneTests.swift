// The scene host parts that bring conversation partners together and say the
// detection lines.

import Foundation
import OpenSkyActorsInterface
import OpenSkyConditions
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
    private static let seat = FurnitureUse(
        sitState: .sitting, animationType: 1, entry: 0x10000, furniture: nil
    )

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

    /// Every head is at one place here, so no actor is far; without heads none is.
    @Test func aSpeakerNearThePlayerIsNotFar() {
        #expect(!adapter.sceneActorStatus(Self.speaker).contains(.farFromPlayer))
        host.fakeDialogueWorld.headPositionResult = .zero
        #expect(!adapter.sceneActorStatus(Self.speaker).contains(.farFromPlayer))
        #expect(!adapter.sceneActorStatus(.player).contains(.farFromPlayer))
    }

    /// Flag 0x02 or a sandbox that allows conversation lets the actor talk.
    @Test func aPackageWithoutTheConversationFlagForbidsTheTalk() {
        #expect(StorySceneCastAdapter.forbidsTalk(flags: 0x04, sandboxAllows: false))
        #expect(!StorySceneCastAdapter.forbidsTalk(flags: 0x06, sandboxAllows: false))
        #expect(!StorySceneCastAdapter.forbidsTalk(flags: 0x04, sandboxAllows: true))
        #expect(!StorySceneCastAdapter.forbidsTalk(flags: nil, sandboxAllows: false))
        #expect(!adapter.sceneActorStatus(Self.speaker).contains(.talkForbidden))
    }

    @Test func anActorThatSitsDownOrStandsUpIsChangingSeat() {
        #expect(!adapter.sceneActorStatus(Self.speaker).contains(.changingSeat))
        for (state, changes) in [
            (FurnitureUse.SitState.readyToSit, true), (.sitting, false), (.readyToStand, true)
        ] {
            var use = Self.seat
            use.sitState = state
            host.fakeIdles.furnitureResolutionValue = FurnitureConditionResolution(
                uses: [Self.speaker: use], isAvailable: true
            )
            #expect(adapter.sceneActorStatus(Self.speaker).contains(.changingSeat) == changes)
        }
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

    /// An actor whose race is not known is no large creature.
    @Test func anActorWithoutARaceIsNoLargeCreature() {
        #expect(!adapter.sceneCast.isLargeCreature(Self.speaker))
        #expect(host.fakeEffectsWorld.raceCalls == [Self.speaker])
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

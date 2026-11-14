// The story world fires story events, drives scenes, and fills the story natives.

import Foundation
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyMenusInterface
import OpenSkyQuests
import OpenSkyQuestsInterface
import OpenSkyScriptingInterface
import OpenSkySessionTesting
@testable import OpenSkyStoryAdapters
import OpenSkyWorldState
import Testing

@MainActor
struct StoryWorldTests {
    private let host = StoryHost()
    private let adapter: StoryWorldAdapter
    private static let actor = ReferenceKey.plugin(name: "base.esm", objectID: 0x20)
    private static let killer = ReferenceKey.plugin(name: "base.esm", objectID: 0x21)
    private static let scene = FormID(0x80)

    init() {
        adapter = StoryWorldAdapter(
            game: host,
            stage: nil,
            now: { Date(timeIntervalSinceReferenceDate: 0) }
        )
        host.fakeRuntimeState.conditionContextResult = ConditionContext()
    }

    @Test func withoutQuestsTheOpeningQuestCannotStart() {
        #expect(!adapter.startOpeningQuest())
        #expect(host.fakeHud.showNotificationCalls.count == 1)
        #expect(throws: (any Error).self) { try adapter.startQuest(FormID(0x90), event: nil) }
        adapter.questFailed(FormID(0x90))
        #expect(host.fakeHud.showNotificationCalls.count == 1)
    }

    @Test func withoutQuestsTheOpeningCannotBeSkipped() {
        #expect(!adapter.skipOpeningQuest(side: .hadvar))
        #expect(host.fakeHud.showNotificationCalls == ["New game: the opening quests are missing"])
        #expect(OpeningSkip.Side.hadvar.quest != OpeningSkip.Side.ralof.quest)
        #expect(OpeningSkip.openingStages.last == 1000)
    }

    @Test func theSocialTickRunsOncePerFrame() {
        let social = FakeSocialEventPort()
        host.fakeStoryManager.social = social
        adapter.socialSearch.tick()
        #expect(social.tickCallCount == 1)
        #expect(host.fakeStoryManager.fireCalls.isEmpty)
    }

    @Test func aKillIsReportedAsMurderAndAStoryEvent() {
        host.fakeCrime.killStatusResult = .murder
        adapter.reportKill(victim: Self.actor, killer: Self.killer)
        #expect(host.fakeCrime.reportMurderCalls == [Self.actor])
        #expect(host.fakeCrime.killStatusCalls.map(\.killer) == [Self.killer])
        #expect(host.fakeStoryManager.fireCalls.map(\.event) == ["KILL"])
    }

    @Test func storyEventsGoToTheStoryManager() {
        var event = StoryEventData(event: "FLAT")
        event.actor1 = Self.actor
        adapter.reportStoryEvent(event)
        #expect(!adapter.sendStoryEvent(event))
        #expect(host.fakeStoryManager.fireCalls.map(\.actor1) == [Self.actor, Self.actor])
    }

    @Test func aSessionStartRunsTheListsWithNoQuestStarted() {
        host.fakeStoryManager.runSessionStartResult = SessionStartReport()
        adapter.runSessionStart(lists: [])
        adapter.runSessionStartLists()
        #expect(host.fakeStoryManager.runSessionStartCalls.count == 1)
    }

    @Test func scenesStartStopAndAnswerThroughTheScenePort() {
        host.fakeScenes.playing = [Self.scene]
        host.fakeScenes.sceneResult = Self.scene
        #expect(adapter.startScene(Self.scene, force: true))
        adapter.stopScene(Self.scene)
        #expect(adapter.isScenePlaying(Self.scene))
        #expect(adapter.currentScene(of: Self.actor) == Self.scene)
        #expect(host.fakeScenes.startCalls.map(\.force) == [true])
        #expect(host.fakeScenes.stopCalls == [Self.scene])
        #expect(host.fakeScenes.sceneCalls == [Self.actor])
    }

    @Test func theConditionContextComesFromTheDialogueWorld() {
        host.fakeDialogueWorld.conditionContextResult = ConditionContext()
        _ = adapter.conditionContext()
        #expect(host.fakeDialogueWorld.conditionContextCallCount == 1)
        #expect(adapter.questStarter != nil)
        #expect(adapter.questRuntime == nil)
    }

    @Test func theNativesForwardToScenesAndFollowers() {
        var story = PapyrusStoryNatives()
        var session = PapyrusSessionNatives()
        host.fakeDialogueWorld.conditionContextResult = ConditionContext()
        adapter.fillStoryNatives(&story, &session)
        story.questStarted?(FormID(0x90))
        story.questFailed?(FormID(0x90))
        story.favorStateChanged?(Self.actor, true)
        _ = session.conditionEvaluator?()
        #expect(host.fakeScenes.questDidStartCalls == [FormID(0x90)])
        #expect(host.fakeFollowerCommandWorld.favorStateChangedCalls.map(\.actor) == [Self.actor])
        #expect(host.fakeDialogueWorld.conditionContextCallCount == 1)
    }

    @Test func socialSightAsksTheAIWorld() {
        host.fakeAiWorld.perceptionHasLineOfSightResult = true
        let one = SocialActor(
            key: Self.actor,
            feet: .zero,
            interruptFlags: nil,
            isDead: false,
            isInScene: false
        )
        #expect(adapter.socialCanSee(one, one))
        #expect(host.fakeAiWorld.perceptionHasLineOfSightCalls.count == 1)
    }

    @Test func theSocialFrameListsActorsAndTheirScenes() throws {
        host.fakeScenes.actorsInScenesResult = [Self.actor]
        host.fakeActorWorld.combatActorsResult = [
            CombatActorObservation(key: Self.actor, feet: .zero),
            CombatActorObservation(key: Self.killer, feet: .zero, isDead: true)
        ]
        let frame = try #require(adapter.socialFrame())
        #expect(frame.actors.map(\.isInScene) == [true, false])
        #expect(frame.actors.map(\.isDead) == [false, true])
        #expect(!frame.isInterior)
        #expect(!frame.playerInConversation)
    }

    /// With no session the search has no origin, and an empty cell gives no candidates.
    @Test func theQuestReferenceSearchReadsTheLoadedCell() throws {
        host.fakeStreamer.residents.residentReferenceIndexResult = .empty
        host.fakeDialogueWorld.conditionContextResult = ConditionContext()
        let search = try #require(adapter.questReferenceSearch())
        #expect(search.origin == nil)
        #expect(search.dead.isEmpty)
        #expect(!search.disables(Self.actor), "a reference outside the cell is not disabled")
    }

    @Test func aQuestReferenceNeedsAPlacedAnchor() {
        #expect(adapter.createQuestReference(FormID(0x40), at: Self.actor) == nil)
        #expect(host.fakeWorldState.allocateGeneratedKeyCallCount == 0)
    }
}

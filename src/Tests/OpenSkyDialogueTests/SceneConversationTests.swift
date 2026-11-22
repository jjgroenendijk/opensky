// Conversation scenes: the scenes of a quest that starts from the actor dialogue
// event. See docs/engine/scenes.md#conversation-scenes.

import Foundation
@testable import OpenSkyDialogue
import OpenSkyDialogueFixtures
import OpenSkyDialogueInterface
import OpenSkyEngineTesting
import OpenSkyFeaturesTesting
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyQuestsInterface
@testable import OpenSkyWorldState
import Testing

@MainActor
struct SceneConversationTests {
    private let speaker = DialogueRuntimeFixture.speakerKey
    private let partner = ReferenceKey.plugin(name: DialogueFixture.pluginName, objectID: 0x7701)

    /// One phase with a 4 second timer, and aliases 0 and 1 as its actors.
    private func scene(_ id: UInt32, isConversation: Bool = true) throws -> CatalogScene {
        try SceneFixture.timerScene(
            id, actors: [TimerSceneActor(alias: 0), TimerSceneActor(alias: 1)],
            isConversation: isConversation
        )
    }

    private func runtime(
        _ store: WorldStateStore, _ scenes: [CatalogScene], host: FakeSceneHost,
        pending: ScenePendingLines = ScenePendingLines(), now: Double = 0,
        partner: ReferenceKey?
    ) throws -> SceneRuntime {
        var runtime = try SceneFixture.runtime(
            store: store, scene: scenes[0], now: now, partner: partner, host: host,
            pendingLines: pending, others: Array(scenes.dropFirst())
        )
        runtime.loopPause = { $0.lowerBound }
        runtime.conversationGap = 6 ... 9
        return runtime
    }

    private func steps(_ events: [SceneEvent], of scene: CatalogScene) -> [SceneStep] {
        events.filter { $0.scene == scene.formID }.map(\.step)
    }

    @Test func itWaitsWhileAPartnerHasNoLoadedBody() throws {
        let store = WorldStateStore()
        let host = FakeSceneHost()
        host.unloaded = [partner]
        let talk = try scene(0x4200)
        let waiting = try runtime(store, [talk], host: host, partner: partner)
            .start(talk.formID)
        #expect(steps(waiting, of: talk) == [.began, .waitingForConversation])
        #expect(try runtime(store, [talk], host: host, now: 45, partner: partner).tick().isEmpty)

        host.unloaded = []
        let begun = try runtime(store, [talk], host: host, now: 46, partner: partner).tick()
        #expect(steps(begun, of: talk).contains(.phaseStarted(0)))
    }

    /// The game stops a waiting scene whose speaker has no body, once its turn has come.
    @Test func itEndsWhenTheSpeakerCannotTalk() throws {
        let talk = try scene(0x4200)
        let host = FakeSceneHost()
        host.unloaded = [speaker]
        let pending = ScenePendingLines()
        pending.conversationFreeAt = 10
        let store = WorldStateStore()
        let waiting = try runtime(store, [talk], host: host, pending: pending, partner: partner)
            .start(talk.formID)
        #expect(steps(waiting, of: talk) == [.began, .waitingForConversation])
        let ended = try runtime(
            store, [talk], host: host, pending: pending, now: 11, partner: partner
        ).tick()
        #expect(steps(ended, of: talk).last == .ended(.stopped))

        let fighting = FakeSceneHost()
        fighting.statuses[partner] = .inCombat
        let events = try runtime(WorldStateStore(), [talk], host: fighting, partner: partner)
            .start(talk.formID)
        #expect(steps(events, of: talk).last == .ended(.stopped))
    }

    /// One partner walks to the other first. One pair walks at a time, and a pair that
    /// does not meet in time gives its turn away.
    @Test func itWaitsWhileThePartnersWalkTogether() throws {
        let store = WorldStateStore()
        let host = FakeSceneHost()
        host.partnersMet = false
        let pending = ScenePendingLines()
        let talk = try scene(0x4200)
        let waiting = try runtime(store, [talk], host: host, pending: pending, partner: partner)
            .start(talk.formID)
        #expect(steps(waiting, of: talk) == [.began, .waitingForPartners])
        #expect(pending.meeting?.scene == talk.formID)
        #expect(try runtime(store, [talk], host: host, pending: pending, now: 5, partner: partner)
            .tick().isEmpty)

        host.partnersMet = true
        let begun = try runtime(
            store, [talk], host: host, pending: pending, now: 6, partner: partner
        ).tick()
        #expect(steps(begun, of: talk).contains(.phaseStarted(0)))
        #expect(pending.meeting == nil)
    }

    @Test func aPairThatDoesNotMeetGivesItsTurnAway() throws {
        let store = WorldStateStore()
        let host = FakeSceneHost()
        host.partnersMet = false
        let pending = ScenePendingLines()
        let talk = try scene(0x4200)
        _ = try runtime(store, [talk], host: host, pending: pending, partner: partner)
            .start(talk.formID)
        _ = try runtime(store, [talk], host: host, pending: pending, now: 31, partner: partner)
            .tick()
        #expect(pending.meeting == nil)
        #expect(pending.meetingRetryAt[talk.formID] == 91)
        host.partnersMet = true
        let early = try runtime(
            store, [talk], host: host, pending: pending, now: 60, partner: partner
        ).tick()
        #expect(early.isEmpty)
        let later = try runtime(
            store, [talk], host: host, pending: pending, now: 92, partner: partner
        ).tick()
        #expect(steps(later, of: talk).contains(.phaseStarted(0)))
    }

    @Test func itWaitsWithoutASecondPartner() throws {
        let talk = try scene(0x4200)
        let events = try runtime(WorldStateStore(), [talk], host: FakeSceneHost(), partner: nil)
            .start(talk.formID)
        #expect(steps(events, of: talk) == [.began, .waitingForConversation])
    }

    @Test func anotherSceneWithUnloadedActorsStillPlays() throws {
        let host = FakeSceneHost()
        host.unloaded = [speaker, partner]
        let plain = try scene(0x4200, isConversation: false)
        let events = try runtime(WorldStateStore(), [plain], host: host, partner: partner)
            .start(plain.formID)
        #expect(steps(events, of: plain).contains(.phaseStarted(0)))
    }

    @Test func aDeadPartnerEndsIt() throws {
        let host = FakeSceneHost()
        host.statuses[partner] = .dead
        let talk = try scene(0x4200)
        let events = try runtime(WorldStateStore(), [talk], host: host, partner: partner)
            .start(talk.formID)
        #expect(steps(events, of: talk).last == .ended(.actorBehavior))
    }

    /// One conversation plays at a time, and the next waits for the gap after it.
    @Test func theNextConversationWaitsForTheGap() throws {
        let store = WorldStateStore()
        let host = FakeSceneHost()
        let pending = ScenePendingLines()
        let first = try scene(0x4200)
        let ended = try runtime(store, [first], host: host, pending: pending, partner: partner)
        try ended.start(first.formID)
        let done = try runtime(
            store, [first], host: host, pending: pending, now: 5, partner: partner
        ).tick()
        #expect(steps(done, of: first).last == .ended(.finished))

        // The gap is 6 s from the end at 5 s.
        let early = try runtime(
            store, [first], host: host, pending: pending, now: 10, partner: partner
        ).start(first.formID)
        #expect(steps(early, of: first) == [.began, .waitingForConversation])
        let late = try runtime(
            store, [first], host: host, pending: pending, now: 11, partner: partner
        ).tick()
        #expect(steps(late, of: first).contains(.phaseStarted(0)))
    }

    /// A scene that needs a partner stops the conversation that holds it.
    @Test func aConversationGivesWayLikeAnInterruptibleScene() throws {
        let store = WorldStateStore()
        let host = FakeSceneHost()
        let talk = try scene(0x4200)
        let plain = try scene(0x4201, isConversation: false)
        let runtime = try runtime(store, [talk, plain], host: host, partner: partner)
        try runtime.start(talk.formID)
        let events = try runtime.start(plain.formID)
        #expect(steps(events, of: talk) == [.ended(.interrupted)])
        #expect(steps(events, of: plain).contains(.phaseStarted(0)))
    }
}

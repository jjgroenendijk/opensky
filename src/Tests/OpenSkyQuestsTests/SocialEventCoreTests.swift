// The NPC social pass: random conversations and the walk to the partner, hellos in
// passing, watching a fight, and finding a body.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
@testable import OpenSkyQuests
import OpenSkyQuestsInterface
import Testing

struct SocialEventCoreTests {
    private let first = ReferenceKey.plugin(name: "test.esm", objectID: 0x100)
    private let second = ReferenceKey.plugin(name: "test.esm", objectID: 0x101)
    private let third = ReferenceKey.plugin(name: "test.esm", objectID: 0x102)
    /// The timer is one second, and every watcher comments.
    private let settings = SocialSettings(
        radius: 500, interiorRadius: 500, timerMin: 1, timerMax: 1, triggerDistance: 200,
        observeCombatChance: 100, spectatorRememberSeconds: 5
    )

    private func actor(
        _ key: ReferenceKey, x: Float, z: Float = 0, flags: UInt16? = 0x02,
        isDead: Bool = false, isInScene: Bool = false, isInCombat: Bool = false
    ) -> SocialActor {
        SocialActor(
            key: key, feet: SIMD3(x, 0, z), interruptFlags: flags,
            isDead: isDead, isInScene: isInScene, isInCombat: isInCombat
        )
    }

    private func pass(
        _ actors: [SocialActor], now: Double, state: inout SocialState,
        interior: Bool = false, player: SIMD3<Float>? = .zero, canSee: Bool = true
    ) -> [SocialEventCommand] {
        let frame = SocialFrame(
            actors: actors, now: now, isInterior: interior, playerInConversation: false,
            player: player
        )
        return SocialEventCore.pass(frame, settings: settings, state: &state) { _, _ in canSee }
    }

    private func events(_ commands: [SocialEventCommand]) -> [String] {
        commands.compactMap { command in
            guard case let .reportStoryEvent(event) = command else { return nil }
            return event.event.description
        }
    }

    @Test func theFirstValidPartnerTalksWithNoChanceRoll() {
        var state = SocialState()
        let actors = [actor(first, x: 0), actor(second, x: 400), actor(third, x: 50)]
        #expect(events(pass(actors, now: 0, state: &state)).isEmpty)
        let commands = pass(actors, now: 2, state: &state)
        #expect(events(commands) == ["ADIA"])
        #expect(state.conversations.first?.partner == second, "key order, not the nearest")
    }

    @Test func aRecentPartnerIsSkippedUntilTheListEmpties() {
        var state = SocialState()
        state.recentPartners[first] = [second]
        state.recentPartners[second] = [first]
        let actors = [actor(first, x: 0), actor(second, x: 100)]
        _ = pass(actors, now: 0, state: &state)
        #expect(events(pass(actors, now: 2, state: &state)).isEmpty)
        #expect(events(pass(actors, now: 130, state: &state)) == ["ADIA"])
    }

    @Test func aPairFarFromThePlayerOrApartInHeightIndoorsDoesNotTalk() {
        var far = SocialState()
        let actors = [actor(first, x: 0), actor(second, x: 100)]
        _ = pass(actors, now: 0, state: &far, player: SIMD3(5000, 0, 0))
        #expect(events(pass(actors, now: 2, state: &far, player: SIMD3(5000, 0, 0))).isEmpty)
        var stairs = SocialState()
        let apart = [actor(first, x: 0), actor(second, x: 100, z: 120)]
        _ = pass(apart, now: 0, state: &stairs, interior: true)
        #expect(events(pass(apart, now: 2, state: &stairs, interior: true)).isEmpty)
    }

    /// The quest answers by putting the speaker in a scene; a far pair then walks.
    @Test func anAnsweredPairTooFarApartWalksTogetherThenTalks() {
        var state = SocialState()
        state.conversations = [SocialConversation(speaker: first, partner: second, startedAt: 0)]
        let far = [actor(first, x: 0, isInScene: true), actor(second, x: 450, isInScene: true)]
        let walk = pass(far, now: 1, state: &state, canSee: false)
        #expect(walk.contains(.hold(second)))
        #expect(walk.contains(.walk(first, to: SIMD3(450, 0, 0))))
        #expect(state.approachingSpeakers == [first])
        let near = [actor(first, x: 300, isInScene: true), actor(second, x: 450, isInScene: true)]
        let talk = pass(near, now: 3, state: &state, canSee: false)
        #expect(talk.contains(.stopWalking(first)))
        #expect(talk.contains(.look(first, at: second)))
        #expect(state.conversations.first?.phase == .talking)
    }

    @Test func aPairNoQuestAnswersIsLetGo() {
        var state = SocialState()
        state.conversations = [SocialConversation(speaker: first, partner: second, startedAt: 0)]
        let actors = [actor(first, x: 0), actor(second, x: 100)]
        _ = pass(actors, now: 1, state: &state)
        #expect(state.conversations.count == 1, "the answer window is still open")
        _ = pass(actors, now: 3, state: &state)
        #expect(state.conversations.isEmpty)
    }

    @Test func aWalkerGreetsANewNearNPC() {
        var state = SocialState()
        // The other NPC takes no conversations, so only the hello fires.
        _ = pass([actor(first, x: 0), actor(second, x: 300, flags: 0)], now: 0, state: &state)
        let commands = pass(
            [actor(first, x: 20), actor(second, x: 300, flags: 0)], now: 1, state: &state
        )
        #expect(events(commands) == ["AHEL"])
        let again = pass(
            [actor(first, x: 40), actor(second, x: 300, flags: 0)], now: 2, state: &state
        )
        #expect(events(again).isEmpty, "the same look target sends no second hello")
    }

    @Test func oneFinderReactsToABodyEveryTwentySeconds() {
        var state = SocialState()
        let actors = [
            actor(first, x: 0, flags: 0x08), actor(third, x: 50, flags: 0x08),
            actor(second, x: 300, isDead: true)
        ]
        let found = pass(actors, now: 0, state: &state)
        #expect(events(found) == ["DEAD"])
        #expect(found.contains(.say("NOTI", first, lookAt: second)))
        #expect(events(pass(actors, now: 10, state: &state)).isEmpty)
        #expect(events(pass(actors, now: 21, state: &state)) == ["DEAD"])
    }

    @Test func aBodyBeyondFourHundredUnitsIsNotFound() {
        var state = SocialState()
        let actors = [actor(first, x: 0, flags: 0x08), actor(second, x: 450, isDead: true)]
        #expect(events(pass(actors, now: 0, state: &state)).isEmpty)
    }

    @Test func aWatcherHoldsCommentsAndStopsWhenTheFightEnds() {
        var state = SocialState()
        let fighting = [actor(first, x: 0, flags: 0x04), actor(second, x: 300, isInCombat: true)]
        let start = pass(fighting, now: 0, state: &state)
        #expect(start.contains(.hold(first)))
        #expect(state.spectators[first]?.fighter == second)
        let comment = pass(fighting, now: 1, state: &state)
        #expect(comment.contains(.say("OBCO", first, lookAt: second)))
        #expect(!pass(fighting, now: 2, state: &state).contains(.say(
            "OBCO",
            first,
            lookAt: second
        )))
        let calm = [actor(first, x: 0, flags: 0x04), actor(second, x: 300)]
        _ = pass(calm, now: 4, state: &state)
        #expect(state.spectators[first] != nil, "the threat is remembered 5 s")
        let stop = pass(calm, now: 8, state: &state)
        #expect(stop.contains(.release(first)))
        #expect(state.spectators[first] == nil)
    }

    @Test func aWalkEndsWhenTheSpeakerFightsAndPathsAgainWhenThePartnerMoves() {
        var state = SocialState()
        state.conversations = [SocialConversation(
            speaker: first, partner: second, startedAt: 0, phase: .approaching,
            goal: SIMD3(450, 0, 0)
        )]
        let moved = [actor(first, x: 0, isInScene: true), actor(second, x: 700, isInScene: true)]
        #expect(pass(moved, now: 1, state: &state).contains(.walk(first, to: SIMD3(700, 0, 0))))
        let fighting = [
            actor(first, x: 100, isInScene: true, isInCombat: true),
            actor(second, x: 700, isInScene: true)
        ]
        let end = pass(fighting, now: 2, state: &state)
        #expect(end.contains(.stopWalking(first)))
        #expect(end.contains(.release(second)))
        #expect(state.conversations.isEmpty)
    }

    @Test func aTalkEndsWithItsSceneOrAtADeath() {
        var state = SocialState()
        state.conversations = [SocialConversation(
            speaker: first, partner: second, startedAt: 0, phase: .talking
        )]
        let end = pass([actor(first, x: 0), actor(second, x: 100)], now: 1, state: &state)
        #expect(end.contains(.release(second)))
        #expect(end.contains(.look(first, at: nil)))
        #expect(state.conversations.isEmpty)
        state.conversations = [SocialConversation(speaker: first, partner: second, startedAt: 1)]
        _ = pass([actor(first, x: 0), actor(second, x: 100, isDead: true)], now: 2, state: &state)
        #expect(state.conversations.isEmpty)
        #expect(state.socialTimers[first] != nil, "a pair that never talked rolls new timers")
    }

    @Test func aFinderLeavesItsConversationForABody() {
        var state = SocialState()
        state.conversations = [SocialConversation(speaker: first, partner: third, startedAt: 0)]
        let actors = [
            actor(first, x: 0, flags: 0x08), actor(third, x: 50),
            actor(second, x: 300, isDead: true)
        ]
        #expect(events(pass(actors, now: 1, state: &state)) == ["DEAD"])
        #expect(state.conversation(of: first) == nil)
    }
}

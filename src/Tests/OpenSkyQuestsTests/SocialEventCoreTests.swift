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

    /// The look target is checked every 1.0 to 1.5 s and held 5 s. Only a new target
    /// of a walker sends the hello.
    @Test func aWalkerGreetsANewNearNPC() {
        var state = SocialState()
        // The other NPC takes no conversations, so only the hello fires.
        _ = pass(
            [actor(first, x: 0), actor(second, x: 900, flags: 0)], now: 0, state: &state,
            player: SIMD3(0, 1000, 0)
        )
        let commands = pass(
            [actor(first, x: 20), actor(second, x: 300, flags: 0)], now: 2, state: &state,
            player: SIMD3(0, 1000, 0)
        )
        #expect(events(commands) == ["AHEL"])
        #expect(commands.contains(.look(first, at: second)))
        let again = pass(
            [actor(first, x: 80), actor(second, x: 300, flags: 0)], now: 8, state: &state,
            player: SIMD3(0, 1000, 0)
        )
        #expect(events(again).isEmpty, "the same look target sends no second hello")
    }

    @Test func thePlayerIsTheFirstLookTargetAndGetsNoHello() {
        var state = SocialState()
        let far = [actor(first, x: 0), actor(second, x: 900, flags: 0)]
        _ = pass(far, now: 0, state: &state, player: SIMD3(0, 1000, 0))
        let near = [actor(first, x: 20), actor(second, x: 300, flags: 0)]
        let commands = pass(near, now: 2, state: &state, player: SIMD3(0, 200, 0))
        #expect(events(commands).isEmpty)
        #expect(state.looks[first]?.target == .player)
    }

    @Test func aLookTargetIsNearInFrontAndNotTooClose() {
        let looker = actor(first, x: 0)
        #expect(SocialEventCore.isLookTarget(actor(second, x: 300), of: looker, old: nil))
        #expect(!SocialEventCore.isLookTarget(actor(second, x: 450), of: looker, old: nil))
        #expect(!SocialEventCore.isLookTarget(actor(second, x: 50), of: looker, old: nil))
        let behind = SocialActor(key: second, feet: SIMD3(0, -300, 0), interruptFlags: 0)
        #expect(!SocialEventCore.isLookTarget(behind, of: looker, old: nil))
        #expect(SocialEventCore.isLookTarget(behind, of: looker, old: second), "an old one stays")
        var seated = looker
        seated.posture = .sitting
        var resting = actor(second, x: 300)
        resting.posture = .sleeping
        #expect(!SocialEventCore.isLookTarget(resting, of: seated, old: nil))
    }

    /// The finder walks to within 100 units before its line.
    @Test func oneFinderWalksToABodyEveryTwentySeconds() {
        var state = SocialState()
        let body = actor(second, x: 300, isDead: true)
        let actors = [actor(first, x: 0, flags: 0x08), actor(third, x: 50, flags: 0x08), body]
        let found = pass(actors, now: 0, state: &state)
        #expect(events(found) == ["DEAD"])
        #expect(found.contains(.walk(first, to: SIMD3(300, 0, 0))))
        #expect(!found.contains(.say("NOTI", first, lookAt: second)))
        #expect(state.isBusy(first))
        let arrived = [actor(first, x: 250, flags: 0x08), actor(third, x: 50, flags: 0x08), body]
        let said = pass(arrived, now: 10, state: &state)
        #expect(said.contains(.say("NOTI", first, lookAt: second)))
        #expect(said.contains(.stopWalking(first)))
        #expect(events(said).isEmpty)
        #expect(events(pass(arrived, now: 21, state: &state)) == ["DEAD"])
    }

    @Test func aFinderTheBodyRemembersSaysNothingAndASlowOneGivesUp() {
        var state = SocialState()
        state.bodyKillers[second] = first
        let body = actor(second, x: 90, isDead: true)
        let near = [actor(first, x: 0, flags: 0x08), body]
        _ = pass(near, now: 0, state: &state)
        #expect(!pass(near, now: 0.5, state: &state).contains(.say("NOTI", first, lookAt: second)))
        #expect(state.finders.isEmpty)
        var slow = SocialState()
        let far = [actor(first, x: 0, flags: 0x08), actor(second, x: 300, isDead: true)]
        _ = pass(far, now: 0, state: &slow)
        let end = pass(far, now: SocialLimits.finderWalkSeconds, state: &slow)
        #expect(end.contains(.say("NOTI", first, lookAt: second)), "within 400 units it speaks")
        #expect(slow.finders.isEmpty)
    }

    @Test func aBodyBeyondFourHundredUnitsIsNotFound() {
        var state = SocialState()
        let actors = [actor(first, x: 0, flags: 0x08), actor(second, x: 450, isDead: true)]
        #expect(events(pass(actors, now: 0, state: &state)).isEmpty)
    }

    @Test func aWatcherHoldsCommentsBacksOffAndStopsWhenTheFightEnds() {
        var state = SocialState()
        let fighting = [actor(first, x: 0, flags: 0x04), actor(second, x: 300, isInCombat: true)]
        let start = pass(fighting, now: 0, state: &state)
        #expect(start.contains(.hold(first)))
        #expect(state.spectators[first]?.threats.map(\.attacker) == [second])
        let comment = pass(fighting, now: 1, state: &state)
        #expect(comment.contains(.say("OBCO", first, lookAt: second)))
        let step = pass(fighting, now: 2, state: &state)
        #expect(!step.contains(.say("OBCO", first, lookAt: second)), "20 s between comments")
        // The fight radius is 512 around the fighter, and the watcher stands inside it.
        #expect(step.contains(.sheathe(first)))
        #expect(step.contains(.walk(first, to: SIMD3(-340, 0, 0))))
        let away = [actor(first, x: -340, flags: 0x04), actor(second, x: 300, isInCombat: true)]
        _ = pass(away, now: 3.5, state: &state)
        let faced = pass(away, now: 5, state: &state)
        #expect(faced.contains(.stopWalking(first)))
        #expect(faced.contains(.face(first, toward: SIMD3(300, 0, 0))) == false)
        #expect(pass(away, now: 5.1, state: &state).contains(.face(
            first,
            toward: SIMD3(300, 0, 0)
        )))
        let calm = [actor(first, x: -340, flags: 0x04), actor(second, x: 300)]
        _ = pass(calm, now: 8, state: &state)
        #expect(state.spectators[first] != nil, "the threat is remembered 5 s")
        let stop = pass(calm, now: 12, state: &state)
        #expect(stop.contains(.release(first)))
        #expect(state.spectators[first] == nil)
    }

    @Test func watchingEndsTwoThousandUnitsFromTheFightCentre() {
        var state = SocialState()
        state.spectators[first] = SocialSpectator(
            threats: [SocialThreat(attacker: second, target: third, lastSeen: 0)], startedAt: 0
        )
        let attacker = SocialActor(
            key: second, feet: SIMD3(0, 0, 0), interruptFlags: 0x02, isInCombat: true,
            combatTarget: third
        )
        let target = SocialActor(
            key: third, feet: SIMD3(400, 0, 0), interruptFlags: 0x02, isInCombat: true,
            combatTarget: second
        )
        let actors = [actor(first, x: -1800, flags: 0x04), attacker, target]
        // The centre lies between the two fighters, at x 200.
        let stop = pass(actors, now: 0.1, state: &state)
        #expect(stop.contains(.release(first)))
        #expect(state.spectators[first] == nil)
    }

    @Test func theFightAreaIsWiderForMeleeThanForRanged() throws {
        var archer = actor(second, x: 0, isInCombat: true)
        archer.fightsRanged = true
        let threat = [SocialThreat(attacker: second, target: nil, lastSeen: 0)]
        let ranged = try #require(SocialFightArea(threat, actors: [second: archer]))
        #expect(ranged.radius == SocialLimits.rangedThreatDistance)
        let melee = try #require(
            SocialFightArea(threat, actors: [second: actor(second, x: 0, isInCombat: true)])
        )
        #expect(melee.radius == SocialLimits.meleeThreatDistance)
        #expect(SocialFightArea(threat, actors: [:]) == nil)
    }
}

extension SocialEventCoreTests {
    @Test func aSeatedSpeakerTriggersFromFartherAway() {
        var speaker = actor(first, x: 0)
        var partner = actor(second, x: 100)
        func distance(sees: Bool) -> Float {
            SocialEventCore.triggerDistance(speaker, partner, settings: settings) { _, _ in sees }
        }
        #expect(distance(sees: false) == 200)
        #expect(distance(sees: true) == 500)
        speaker.posture = .sitting
        #expect(distance(sees: false) == 220)
        partner.posture = .sleeping
        #expect(distance(sees: false) == 520)
    }

    /// The story manager's walk ends in the frame of the event.
    @Test func aPairEndsAtOnceWhenNoQuestStartsButAPackageRequestWaits() {
        var state = SocialState()
        state.conversations = [SocialConversation(speaker: first, partner: second, startedAt: 0)]
        SocialEventCore.answer(
            pair: (first, second), started: false, settings: settings, state: &state
        )
        #expect(state.conversations.isEmpty)
        #expect(state.socialTimers[first] != nil)
        #expect(state.socialTimers[second] == nil, "only the speaker rolls a new timer")
        state.conversations = [SocialConversation(
            speaker: first, partner: second, startedAt: 0, isPackageRequest: true
        )]
        SocialEventCore.answer(
            pair: (first, second), started: false, settings: settings, state: &state
        )
        #expect(state.conversations.count == 1)
        SocialEventCore.answer(
            pair: (first, second), started: true, settings: settings, state: &state
        )
        #expect(state.conversations.count == 1)
        #expect(state.socialTimers[second] != nil, "with a quest both roll new timers")
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

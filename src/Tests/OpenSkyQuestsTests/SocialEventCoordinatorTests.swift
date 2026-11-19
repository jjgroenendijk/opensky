// The shell of the social pass: the pass every 30 frames, a `DialogueActivate`
// conversation, and the state a save restores.

import OpenSkyConditions
import OpenSkyFormatsCore
import OpenSkyFormatsESM
@testable import OpenSkyQuests
import OpenSkyQuestsInterface
import Testing

@MainActor
struct SocialEventCoordinatorTests {
    private final class World: SocialEventWorld {
        var frame: SocialFrame?

        func socialFrame() -> SocialFrame? {
            frame
        }

        func socialCanSee(_: SocialActor, _: SocialActor) -> Bool {
            true
        }
    }

    private let first = ReferenceKey.plugin(name: "test.esm", objectID: 0x100)
    private let second = ReferenceKey.plugin(name: "test.esm", objectID: 0x101)
    private let third = ReferenceKey.plugin(name: "test.esm", objectID: 0x102)

    private func events(_ commands: [SocialEventCommand]) -> [String] {
        commands.compactMap { command in
            guard case let .reportStoryEvent(event) = command else { return nil }
            return event.event.description
        }
    }

    @Test func dialogueActivateSendsADIAOnTheNextTick() {
        let social = SocialEventCoordinator(world: World())
        #expect(social.requestConversation(speaker: first, partner: second, now: 5))
        #expect(events(social.tick()) == ["ADIA"])
        #expect(social.tick().isEmpty, "the commands go out once")
        #expect(social.sentCounts[FourCC("ADIA")] == 1)
        #expect(social.recent.map(\.event.description) == ["ADIA"])
        let talk = social.state.conversations.first
        #expect(talk?.answerSeconds == SocialLimits.dialogueActivateAnswerSeconds)
        #expect(social.state.recentPartners[second] == [first])
    }

    @Test func aBusyOrSameActorStartsNoConversation() {
        let social = SocialEventCoordinator(world: World())
        #expect(!social.requestConversation(speaker: first, partner: first, now: 0))
        social.requestConversation(speaker: first, partner: second, now: 0)
        #expect(!social.requestConversation(speaker: third, partner: second, now: 0))
        #expect(social.state.conversations.count == 1)
    }

    @Test func theWalkersAndWatchersAreReadFromTheState() {
        let social = SocialEventCoordinator(world: World())
        var saved = SocialState()
        saved.conversations = [SocialConversation(
            speaker: first, partner: second, startedAt: 0, phase: .approaching
        )]
        saved.spectators[third] = SocialSpectator(fighter: first, lastSeenFighting: 0)
        social.restore(saved)
        #expect(social.approachingSpeakers == [first])
        #expect(social.isWatchingCombat(third))
        #expect(!social.isWatchingCombat(second))
        social.reset()
        #expect(social.state == SocialState())
        #expect(social.approachingSpeakers.isEmpty)
    }

    @Test func thePassRunsEveryThirtyFramesWhileAWorldIsLoaded() {
        let world = World()
        let social = SocialEventCoordinator(world: world)
        let body = SocialActor(
            key: second, feet: SIMD3(100, 0, 0), interruptFlags: 0, isDead: true
        )
        world.frame = SocialFrame(
            actors: [SocialActor(key: first, feet: .zero, interruptFlags: 0x08), body],
            now: 0, isInterior: false, playerInConversation: false, player: .zero
        )
        for _ in 1 ..< SocialEventCoordinator.frameInterval {
            #expect(social.tick().isEmpty)
        }
        #expect(events(social.tick()) == ["DEAD"])
        world.frame = nil
        social.runPass()
        #expect(social.tick().isEmpty, "no world, no pass")
    }
}

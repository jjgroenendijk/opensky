// The shell of the social pass: the pass every frame, a `DialogueActivate`
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
        saved.spectators[third] = SocialSpectator(threats: [], startedAt: 0)
        social.restore(saved)
        #expect(social.approachingSpeakers == [first])
        #expect(social.isWatchingCombat(third))
        #expect(!social.isWatchingCombat(second))
        social.reset()
        #expect(social.state == SocialState())
        #expect(social.approachingSpeakers.isEmpty)
    }

    /// A waiting conversation scene asks its pair to meet: the speaker walks, and the
    /// pair counts as met once it stands near. A meeting nobody asks for ends.
    @Test func aSceneMeetingWalksThePairTogether() {
        let world = World()
        let social = SocialEventCoordinator(world: world)
        func frame(_ distance: Float, now: Double) -> SocialFrame {
            SocialFrame(
                actors: [
                    SocialActor(key: first, feet: .zero, interruptFlags: 0x02),
                    SocialActor(key: second, feet: SIMD3(distance, 0, 0), interruptFlags: 0x02)
                ],
                now: now, isInterior: false, playerInConversation: false, player: .zero
            )
        }
        #expect(!social.meetForScene(speaker: first, partner: second, now: 0))
        #expect(social.state.sceneMeetings == [first])
        world.frame = frame(2000, now: 0)
        social.runPass()
        #expect(social.state.conversations.first?.phase == .approaching)
        #expect(social.approachingSpeakers.isEmpty, "the scene has not begun, so nothing pauses")
        #expect(social.tick().contains(.walk(first, to: SIMD3(2000, 0, 0))))

        world.frame = frame(100, now: 1)
        #expect(!social.meetForScene(speaker: second, partner: first, now: 1))
        social.runPass()
        #expect(social.meetForScene(speaker: first, partner: second, now: 1))

        world.frame = frame(100, now: 10)
        social.runPass()
        #expect(social.state.sceneMeetings.isEmpty)
        #expect(social.state.conversations.isEmpty)
    }

    @Test func thePassRunsEveryFrameWhileAWorldIsLoaded() {
        let world = World()
        let social = SocialEventCoordinator(world: world)
        let body = SocialActor(
            key: second, feet: SIMD3(100, 0, 0), interruptFlags: 0, isDead: true
        )
        world.frame = SocialFrame(
            actors: [SocialActor(key: first, feet: .zero, interruptFlags: 0x08), body],
            now: 0, isInterior: false, playerInConversation: false, player: .zero
        )
        #expect(events(social.tick()) == ["DEAD"])
        world.frame = nil
        #expect(social.tick().isEmpty, "no world, no pass")
    }

    @Test func theStoryManagersAnswerEndsAPairAndAKillIsRemembered() {
        let social = SocialEventCoordinator(world: World())
        var saved = SocialState()
        saved.conversations = [SocialConversation(speaker: first, partner: second, startedAt: 0)]
        social.restore(saved)
        var event = StoryEventData(event: "ADIA")
        event.actor1 = first
        event.actor2 = second
        social.storyEventAnswered(StoryEventData(event: "AHEL"), startedQuest: false)
        #expect(social.state.conversations.count == 1)
        social.storyEventAnswered(event, startedQuest: false)
        #expect(social.state.conversations.isEmpty)
        social.noteKill(victim: third, killer: first)
        #expect(social.state.bodyKillers[third] == first)
    }
}

extension SocialEventCoordinatorTests {
    /// A walk asked while a seat's exit clip plays is refused, so a speaker that
    /// stands still is asked again; one that walks is not.
    @Test func aSpeakerThatStandsStillIsAskedToWalkAgain() {
        let world = World()
        let social = SocialEventCoordinator(world: world)
        func frame(speakerAt x: Float, now: Double) -> SocialFrame {
            SocialFrame(
                actors: [
                    SocialActor(key: first, feet: SIMD3(x, 0, 0), interruptFlags: 0x02),
                    SocialActor(key: second, feet: SIMD3(2000, 0, 0), interruptFlags: 0x02)
                ],
                now: now, isInterior: false, playerInConversation: false, player: .zero
            )
        }
        let walk = SocialEventCommand.walk(first, to: SIMD3(2000, 0, 0))
        _ = social.meetForScene(speaker: first, partner: second, now: 0)
        world.frame = frame(speakerAt: 0, now: 0)
        social.runPass()
        #expect(social.tick().contains(walk))

        _ = social.meetForScene(speaker: first, partner: second, now: 0.5)
        world.frame = frame(speakerAt: 0, now: 0.5)
        social.runPass()
        #expect(!social.tick().contains(walk), "one second has not passed")

        _ = social.meetForScene(speaker: first, partner: second, now: 1.5)
        world.frame = frame(speakerAt: 0, now: 1.5)
        social.runPass()
        #expect(social.tick().contains(walk))

        _ = social.meetForScene(speaker: first, partner: second, now: 3)
        world.frame = frame(speakerAt: 100, now: 3)
        social.runPass()
        #expect(!social.tick().contains(walk), "the speaker walks")
    }
}

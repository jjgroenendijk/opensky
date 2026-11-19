// The coordinator's record of fired events, and the `QSTR` event that walks no node.

import OpenSkyConditions
import OpenSkyFormatsCore
import OpenSkyFormatsESM
@testable import OpenSkyQuests
import OpenSkyQuestsInterface
import Testing

@MainActor
struct StoryManagerCoordinatorTests {
    private final class NoWorld: StoryManagerWorld, SocialEventWorld {
        var questRuntime: QuestRuntime? {
            nil
        }

        var questStarter: (any QuestStarting)? {
            nil
        }

        func conditionContext() -> ConditionContext {
            ConditionContext()
        }

        func socialFrame() -> SocialFrame? {
            nil
        }

        func socialCanSee(_: SocialActor, _: SocialActor) -> Bool {
            false
        }
    }

    private func coordinator() -> (StoryManagerCoordinator, NoWorld) {
        let world = NoWorld()
        return (
            StoryManagerCoordinator(
                world: world, social: SocialEventCoordinator(world: world), story: nil
            ),
            world
        )
    }

    @Test func firedEventsAreCountedAndTheNewestKept() {
        let (story, _) = coordinator()
        for _ in 0 ..< 20 {
            story.fire(.payFine(
                guardActor: nil, crimeFaction: .plugin(name: "test.esm", objectID: 0x10), bounty: 40
            ))
        }
        story.fire(.questStart(FormID(0x0100)))

        #expect(story.firedCounts["PFIN"] == 20)
        #expect(story.firedCounts["QSTR"] == 1)
        #expect(story.recentEvents.count == StoryManagerCoordinator.recentEventLimit)
        #expect(story.recentEvents.last?.quest == FormID(0x0100))
    }

    @Test func aVoicePowerAndATrespassCarryTheirData() {
        let actor = ReferenceKey.plugin(name: "test.esm", objectID: 0x20)
        let power = StoryEventData.newVoicePower(actor: actor, power: FormID(0x0300))
        #expect(power.event == "NVPE")
        #expect(power.actor1 == actor)
        #expect(power.form == FormID(0x0300))
        let trespass = StoryEventData.trespass(witness: actor, location: nil, crimeGold: 5)
        #expect(trespass.event == "TRES")
        #expect(trespass.actor1 == actor)
        #expect(trespass.actor2 == .player)
        #expect(trespass.value1 == 5)
    }

    @Test func aQuestStartWalksNoNode() {
        let (story, _) = coordinator()
        #expect(story.fire(.questStart(FormID(0x0100))) == nil)
    }
}

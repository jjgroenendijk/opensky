// App side of the NPC social pass: the loaded actors with their package's
// interrupt flags, and sight lines through the perception world. The rules live
// in `SocialEventCore` (docs/engine/random-conversations.md).

import OpenSkyCombat
import OpenSkyConditions
import OpenSkyDialogue
import OpenSkyFormatsESM
import OpenSkyPerceptionInterface
import OpenSkyPhysics
import OpenSkyQuests
import OpenSkyWorld
import simd

extension StoryWorldAdapter: SocialEventWorld {
    func socialFrame() -> SocialFrame? {
        guard game.streamer != nil else { return nil }
        let inScenes = scenes.actorsInScenes()
        let actors = game.actorWorld.combatActors().map { actor in
            SocialActor(
                key: actor.key,
                feet: actor.feet,
                interruptFlags: game.packages.runtime?.currentPackage(for: actor.key)?
                    .package.general.interruptFlags,
                isDead: actor.isDead,
                isInScene: inScenes.contains(actor.key)
            )
        }
        return SocialFrame(
            actors: actors,
            now: sceneSeconds,
            isInterior: game.streamer?.interiorScene != nil,
            playerInConversation: game.dialogue.conversationSpeaker != nil
        )
    }

    /// Eye to the body's chest, about half a standing actor's eye height.
    func socialCanSee(_ observer: SocialActor, _ body: SocialActor) -> Bool {
        let eye = observer.feet + SIMD3(0, 0, PlayerCapsule.standard.eyeHeight)
        let chest = body.feet + SIMD3(0, 0, PlayerCapsule.standard.eyeHeight / 2)
        return game.aiWorld.perceptionHasLineOfSight(from: eye, to: chest)
    }

    func reportSocialEvent(_ event: StoryEventData) {
        reportStoryEvent(event)
    }
}

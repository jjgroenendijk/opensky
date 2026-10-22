// App side of bump reactions: which calm NPCs the player's capsule touches this frame,
// and the line and step aside the rule asks for (docs/engine/bump-reactions.md).

import OpenSkyAIPackages
import OpenSkyCombat
import OpenSkyDialogue
import OpenSkyFormatsESM
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyWorld
import simd

extension AIWorldAdapter {
    /// Extra room past the two capsules that still counts as a touch, in units.
    static let bumpSlack: Float = 4

    func advanceBumps() {
        guard let gameSession = game.gameSession, game.streamer != nil else { return }
        let player = gameSession.walkController
        let loop = game.combat.loop
        let busy = game.storyWorld.scenes.actorsInScenes()
        let contacts = game.actorWorld.combatActors().compactMap { actor -> BumpContact? in
            guard
                !actor.isDead, !busy.contains(actor.key),
                actor.key != game.dialogue.conversationSpeaker,
                loop?.phase(of: actor.key)?.isEngaged != true
            else { return nil }
            let offset = actor.feet - player.feetPosition
            let reach = player.capsule.radius + actor.capsule.radius * actor.scale + Self.bumpSlack
            guard
                simd_length(SIMD2(offset.x, offset.y)) <= reach,
                abs(offset.z) < player.capsule.height
            else { return nil }
            return BumpContact(
                actor: actor.key, actorFeet: actor.feet, playerFeet: player.feetPosition
            )
        }
        for command in game.packages.advanceBumps(contacts, now: game.storyWorld.sceneSeconds) {
            switch command {
            case let .speak(actor): game.storyWorld.sayOwnLine(.bump, speaker: actor)
            case let .move(actor, goal): _ = game.streamer?.moveActor(actor, to: goal)
            }
        }
    }
}

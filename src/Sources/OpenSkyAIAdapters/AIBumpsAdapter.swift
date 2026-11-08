import OpenSkyActorPresentation
import OpenSkyActors
import OpenSkyActorsInterface
public import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyCrime
import OpenSkyDialogue
import OpenSkyDialogueInterface
import OpenSkyFactions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyMagic
import OpenSkyNavigation
import OpenSkyPerception
import OpenSkyPerceptionInterface
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyProgression
import OpenSkyProgressionInterface
import OpenSkyQuestsInterface
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyScripting
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldConditions
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// What `AIBumpsAdapter` reads from the session.
@MainActor
public protocol AIBumpsHost: AnyObject {
    var actorWorld: any ActorWorldPort { get }
    var combat: any CombatPort { get }
    var dialogue: any DialoguePort { get }
    var gameSession: (any GameSessionPort)? { get }
    var packages: any PackagePort { get }
    var storyWorld: any StoryWorldPort { get }
    var streamer: (any CellStreamerPort)? { get }
    var vehicleWorld: any VehicleWorldPort { get }
}

/// Part of `AIWorldAdapter`, over its own narrow host.
public struct AIBumpsAdapter {
    public unowned let owner: AIWorldAdapter
    public unowned let game: any AIBumpsHost
}

extension AIBumpsAdapter {
    /// Extra room past the two capsules that still counts as a touch, in units.
    public static let bumpSlack: Float = 4

    public func advanceBumps() {
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

    /// The living actors and the player, for walkers to steer around. Each mover is
    /// dropped from this list by the movement runtime, which knows who walks. A rider
    /// is left out: it takes up its vehicle's space, and a horse must not steer around
    /// the rider in its own saddle.
    public func standingActors() -> [NPCNeighbour] {
        let links = game.vehicleWorld.vehicles.core.links
        var actors = game.actorWorld.combatActors().filter {
            !$0.isDead && links[$0.key] == nil
        }.map {
            NPCNeighbour(
                key: $0.key, position: SIMD2($0.feet.x, $0.feet.y),
                radius: $0.capsule.radius * max($0.scale, 0)
            )
        }
        if links[.player] == nil, let feet = game.gameSession?.locomotion.status.feetPosition {
            actors.append(NPCNeighbour(
                key: .player, position: SIMD2(feet.x, feet.y),
                radius: PlayerCapsule.standard.radius
            ))
        }
        return actors
    }
}

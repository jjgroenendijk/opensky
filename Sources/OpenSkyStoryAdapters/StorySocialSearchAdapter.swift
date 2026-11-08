import OpenSkyAIPackages
import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyDialogue
public import OpenSkyFormatsESM
import OpenSkyPhysics
import OpenSkyPlayer
public import OpenSkyQuests
public import OpenSkyQuestsInterface
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyScripting
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// What `StorySocialSearchAdapter` reads from the session.
@MainActor
public protocol StorySocialSearchHost: AnyObject {
    var actorWorld: any ActorWorldPort { get }
    var aiWorld: any AIWorldPort { get }
    var dialogue: any DialoguePort { get }
    var gameSession: (any GameSessionPort)? { get }
    var packages: any PackagePort { get }
    var scripts: any ScriptPort { get }
    var streamer: (any CellStreamerPort)? { get }
    var worldState: any WorldStateStorePort { get }
}

/// Part of `StoryWorldAdapter`, over its own narrow host.
public struct StorySocialSearchAdapter {
    public unowned let owner: StoryWorldAdapter
    public unowned let game: any StorySocialSearchHost
}

extension StorySocialSearchAdapter {
    /// Nil while no cell is loaded.
    public func questReferenceSearch() -> QuestReferenceSearch? {
        guard let streamer = game.streamer else { return nil }
        let references = streamer.residentReferenceIndex()
        let store = game.worldState
        let enable = EnableParentResolver(
            delta: { store.delta(for: $0) },
            parent: { [weak streamer] in streamer?.referenceEntry(formID: $0) }
        )
        var context = owner.conditionContext()
        context.references = references
        let entries = references.sortedEntries()
        let feet = game.gameSession.map { gameSession in
            gameSession.movementMode.isPlayerControlled
                ? gameSession.walkController.feetPosition : gameSession.freeFlyCamera.position
        }
        return QuestReferenceSearch(
            references: references,
            origin: feet,
            context: context,
            registry: owner.conditionRegistry,
            dead: Set(game.actorWorld.combatActors().filter(\.isDead).map(\.key)),
            disabled: Set(entries.filter { !enable.isEnabled($0) }.map(\.key))
        )
    }

    /// A new reference of `base` where `anchor` stands, loaded or not. It is a spawn, so
    /// the save keeps it and a cell build places it like a dropped item or an actor.
    public func createQuestReference(_ base: FormID, at anchor: ReferenceKey) -> ReferenceKey? {
        guard
            let placement = game.scripts.bridge?.placement(of: anchor),
            let location = placement.location
        else { return nil }
        let spawn = ReferenceSpawnState(
            base: base, location: location, placement: placement.state.transform.placement
        )
        let key = game.worldState.allocateGeneratedKey()
        game.worldState.set(spawn, for: key, in: location)
        return key
    }
}

extension StorySocialSearchAdapter {
    public func socialFrame() -> SocialFrame? {
        guard game.streamer != nil else { return nil }
        let inScenes = owner.scenes.actorsInScenes()
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
            now: owner.sceneSeconds,
            isInterior: game.streamer?.interiorScene != nil,
            playerInConversation: game.dialogue.conversationSpeaker != nil
        )
    }

    /// Eye to the body's chest, about half a standing actor's eye height.
    public func socialCanSee(_ observer: SocialActor, _ body: SocialActor) -> Bool {
        let eye = observer.feet + SIMD3(0, 0, PlayerCapsule.standard.eyeHeight)
        let chest = body.feet + SIMD3(0, 0, PlayerCapsule.standard.eyeHeight / 2)
        return game.aiWorld.perceptionHasLineOfSight(from: eye, to: chest)
    }

    public func run(_ commands: [SocialEventCommand]) {
        for case let .reportStoryEvent(event) in commands {
            owner.reportStoryEvent(event)
        }
    }
}

import OpenSkyActorsInterface
import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyCombatInterface
public import OpenSkyCrime
import OpenSkyCrimeInterface
import OpenSkyDialogue
import OpenSkyFactionsInterface
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyPlayer
import OpenSkyQuestsInterface
import OpenSkyRendering
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// What `CrimeActorsAdapter` reads from the session.
@MainActor
public protocol CrimeActorsHost: AnyObject {
    var actorWorld: any ActorWorldPort { get }
    var dialogue: any DialoguePort { get }
    var dialogueMenu: any DialogueMenuPort { get }
    var packages: any PackagePort { get }
    var perception: any PerceptionPort { get }
    var streamer: (any CellStreamerPort)? { get }
    var worldState: any WorldStateStorePort { get }
}

/// Part of `CrimeWorldAdapter`, over its own narrow host.
public struct CrimeActorsAdapter {
    public let game: any CrimeActorsHost
}

extension CrimeActorsAdapter {
    public func actorsDetectingPlayer() -> [CrimeObserver] {
        guard let perception = game.perception.runtime else { return [] }
        let detecting = Set(perception.observersDetecting(.player))
        return game.actorWorld.combatActors()
            .filter { !$0.isDead && detecting.contains($0.key) }
            .map { CrimeObserver(key: $0.key, feet: $0.feet) }
    }

    public func livingActors() -> [CrimeObserver] {
        game.actorWorld.combatActors()
            .filter { !$0.isDead }
            .map { CrimeObserver(key: $0.key, feet: $0.feet) }
    }

    public func isDead(_ key: ReferenceKey) -> Bool {
        game.worldState.component(ActorDeathState.self, for: key)?.isDead == true
    }

    public func moveActor(_ key: ReferenceKey, to point: SIMD3<Float>) -> String? {
        game.streamer.map { "\($0.moveActor(key, to: point))" }
    }

    public func stopActor(_ key: ReferenceKey) {
        _ = game.streamer?.stopActor(key)
    }

    public func suspendPackage(for key: ReferenceKey) {
        game.packages.suspend(key)
    }

    public func resumePackage(for key: ReferenceKey) {
        game.packages.resume(key)
    }

    public var isDialogueOpen: Bool {
        game.dialogueMenu.isOpen
    }

    public var lastDialogueOutcome: String? {
        game.dialogue.lastOutcome
    }

    public func beginDialogue(with speaker: ReferenceKey) {
        game.dialogueMenu.begin(with: speaker)
    }
}

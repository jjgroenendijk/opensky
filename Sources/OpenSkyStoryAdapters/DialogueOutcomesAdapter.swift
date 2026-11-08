import OpenSkyActorPresentation
public import OpenSkyActorsInterface
import OpenSkyAIPackages
public import OpenSkyCells
import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyDiagnostics
import OpenSkyDialogue
public import OpenSkyDialogueInterface
import OpenSkyFactions
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyProgression
import OpenSkyProgressionInterface
import OpenSkyQuestsInterface
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

/// What `DialogueOutcomesAdapter` reads from the session.
@MainActor
public protocol DialogueOutcomesHost: AnyObject {
    var dialogue: any DialoguePort { get }
    var inventory: any InventoryPort { get }
    var packages: any PackagePort { get }
    var perks: any PerkPort { get }
    var progression: any ProgressionPort { get }
    var storyWorld: any StoryWorldPort { get }
    var streamer: (any CellStreamerPort)? { get }
    var worldData: WorldDataStores? { get }
    var worldState: any WorldStateStorePort { get }
}

/// Part of `DialogueWorldAdapter`, over its own narrow host.
public struct DialogueOutcomesAdapter {
    public unowned let owner: DialogueWorldAdapter
    public unowned let game: any DialogueOutcomesHost
}

extension DialogueOutcomesAdapter {
    /// The perk factors are for the actor the player talks to.
    public func speechCheckResolution() -> SpeechCheckResolution {
        let speaker = game.dialogue.conversationSpeaker
        let gold = game.inventory.runtime.map { runtime in
            Int(runtime.inventory.count(of: runtime.inventory.goldFormID, in: runtime.player))
        }
        return SpeechCheckResolution(
            settings: game.worldData?.speechCheckSettings,
            playerGold: gold,
            intimidationFactor: game.perks.multiplier(
                at: .modPlayerIntimidation, on: .player, target: speaker
            ),
            bribeFactor: game.perks.multiplier(at: .modBribeAmount, on: .player, target: speaker)
        )
    }

    public func run(_ commands: [DialogueCommand]) {
        for command in commands {
            switch command {
            case let .suspendPackage(actor): game.packages.suspend(actor)
            case let .resumePackage(actor): game.packages.resume(actor)
            case let .stopActor(actor): game.streamer?.stopActor(actor)
            case let .faceActor(actor, point): game.streamer?.faceActor(actor, towards: point)
            case let .releaseFacing(actor): game.streamer?.releaseActorFacing(actor)
            case let .speechChallengeWon(challenge, speaker):
                speechChallengeWon(challenge, speaker: speaker)
            case let .spokeToPlayer(speaker): owner.spokeToPlayer(speaker)
            }
        }
    }

    /// `BRIB`, `INTM`, or `FLAT`, with the actor the player won over as `R1`.
    private func speechChallengeWon(_ challenge: SpeechChallenge, speaker: ReferenceKey) {
        var event = StoryEventData(event: FourCC(stringLiteral: challenge.eventCode))
        event.actor1 = speaker
        game.storyWorld.reportStoryEvent(event)
        game.worldState.incrementMiscStat(challenge.statName)
        game.progression.reportSpeechCheckWon()
    }
}

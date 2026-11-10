import OpenSkyActorPresentation
public import OpenSkyActorsInterface
import OpenSkyAIPackages
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyDialogue
public import OpenSkyDialogueInterface
import OpenSkyFormatsCore
import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyProgressionInterface
import OpenSkyQuestsInterface
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldConditions
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// What `DialogueOutcomesAdapter` reads from the session.
@MainActor
public protocol DialogueOutcomesHost: AnyObject, SendableMetatype {
    var dialogue: any DialoguePort { get }
    var inventory: any InventoryPort { get }
    var packages: any PackagePort { get }
    var perks: any PerkPort { get }
    var progression: any ProgressionPort { get }
    var storyWorld: any StoryWorldPort { get }
    var streamer: any CellStreamerPort { get }
    var worldRecords: (any WorldRecordsPort)? { get }
    var worldState: any WorldStateStorePort { get }
    var scripts: any ScriptPort { get }
}

/// Part of `DialogueWorldAdapter`, over its own narrow host.
public struct DialogueOutcomesAdapter {
    public let game: any DialogueOutcomesHost
}

extension DialogueOutcomesAdapter {
    /// The perk factors are for the actor the player talks to.
    public func speechCheckResolution() -> SpeechCheckResolution {
        let speaker = game.dialogue.conversationSpeaker
        let gold = game.inventory.runtime.map { runtime in
            Int(runtime.inventory.count(of: runtime.inventory.goldFormID, in: runtime.player))
        }
        return SpeechCheckResolution(
            settings: game.worldRecords?.speechCheckSettings,
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
            case let .stopActor(actor): game.streamer.stopActor(actor)
            case let .faceActor(actor, point): game.streamer.faceActor(actor, towards: point)
            case let .releaseFacing(actor): game.streamer.releaseActorFacing(actor)
            case let .speechChallengeWon(challenge, speaker):
                speechChallengeWon(challenge, speaker: speaker)
            case let .spokeToPlayer(speaker): spokeToPlayer(speaker)
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

    func spokeToPlayer(_ speaker: ReferenceKey) {
        game.scripts.bridge?.updateScriptedState(of: speaker) {
            $0.setFlag(ScriptedStateName.talkedToPlayer, true)
        }
    }
}

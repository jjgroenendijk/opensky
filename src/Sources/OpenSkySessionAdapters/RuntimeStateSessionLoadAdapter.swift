import Foundation
import OpenSkyActorPresentation
import OpenSkyActorsInterface
import OpenSkyAIPackages
import OpenSkyAudio
import OpenSkyCells
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyCrimeInterface
import OpenSkyDialogueInterface
import OpenSkyFactionsInterface
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyMenusInterface
import OpenSkyPerceptionInterface
import OpenSkyPlayer
import OpenSkyQuestsInterface
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkySave
import OpenSkySaveInterface
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWeather
import OpenSkyWorld
import OpenSkyWorldConditions
import OpenSkyWorldInterface
import OpenSkyWorldState

/// What `RuntimeStateSessionLoadAdapter` reads from the session.
@MainActor
public protocol RuntimeStateSessionLoadHost: AnyObject, SendableMetatype {
    var combat: any CombatPort { get }
    var combatWorld: any CombatWorldPort { get }
    var gameSession: (any GameSessionPort)? { get }
    var inventory: any InventoryPort { get }
    var magic: any MagicPort { get }
    var menuWorld: any MenuWorldPort { get }
    var messages: any MessageCoordinatorPort { get }
    var player: any PlayerPort { get }
    var questNotices: any QuestNoticePort { get }
    var ragdoll: any RagdollPort { get }
    var scripts: any ScriptPort { get }
    var worldState: any WorldStateStorePort { get }
}

/// Part of `RuntimeStateWorldAdapter`, over its own narrow host.
public struct RuntimeStateSessionLoadAdapter {
    public let game: any RuntimeStateSessionLoadHost
    public let core: RuntimeStateCoreAdapter
    public let saveContents: RuntimeStateSaveContentsAdapter
}

extension RuntimeStateSessionLoadAdapter {
    /// A missing install skips fingerprint verification instead of blocking the
    /// load; the file's own contents are still checked.
    public func loadSession(slot: String) async throws {
        try await loadSession(slot: slot, checksLoadOrder: true)
    }

    /// A changed load order throws `SaveFailure.contentMissing`, or `.noMasterFiles` when
    /// no plugin of the save is loaded; `checksLoadOrder: false` loads it anyway.
    public func loadSession(slot: String, checksLoadOrder: Bool) async throws {
        let current = checksLoadOrder ? await attempt { try await core.pluginFingerprint() } : nil
        let file: OpenSkySaveFile
        do {
            file = try await core.store().read(slot: slot, verifyingAgainst: current)
        } catch OpenSkySaveError.fingerprintMismatch {
            let saved = try await core.store().read(slot: slot, verifyingAgainst: nil)
            let loaded = Set((current ?? []).map { $0.name.lowercased() })
            let shared = saved.fingerprint.contains { loaded.contains($0.name.lowercased()) }
            throw shared ? SaveFailure.contentMissing : SaveFailure.noMasterFiles
        }
        game.worldState.restore(from: file.snapshot)
        // No plugin holds a brewed potion, so the save's own list goes in the item index.
        game.inventory.alchemyLab.registerCreatedPotions()
        // A save without a CLOK chunk restores the vanilla-start clock.
        game.gameSession?.gameClock = file.clock ?? GameClock()
        game.gameSession?.clearScriptScreenEffects()
        // After the world state, so the fired `OnInit` set is in place before the
        // queued cell rebuilds re-attach scripts.
        game.scripts.restore(instances: file.scripts, timers: file.timers)
        game.scripts.bridge?.publishFactionReactions()
        game.scripts.bridge?.publishLeveledEdits()
        saveContents.restoreRuntimeExtras()
        game.combatWorld.run(game.combat.prepareForPersistence())
        game.messages.reloadHelpRecords()
        game.questNotices.reset()
        game.ragdoll.resetPlayerDeath()
        // A load reloads the player's 3D, which drops a script's eye texture.
        game.player.eyeTextureSet = nil
        // `AVOV` keeps no temporary modifiers, so the restored effects rebuild
        // them: the player now, every other actor when its cell streams back in.
        game.magic.noteEffectsRestored()
        if let place = file.playerPlace {
            game.menuWorld.restorePlayerPlace(place)
        }
    }
}

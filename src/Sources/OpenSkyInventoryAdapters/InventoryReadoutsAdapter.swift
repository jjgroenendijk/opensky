import OpenSkyActors
import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyConditions
import OpenSkyCrime
import OpenSkyCrimeInterface
import OpenSkyFactions
import OpenSkyFactionsInterface
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
public import OpenSkyInventoryInterface
import OpenSkyMagic
public import OpenSkyMagicInterface
import OpenSkyMenus
import OpenSkyMenusInterface
import OpenSkyPerception
import OpenSkyPerceptionInterface
import OpenSkyPlayer
import OpenSkyProgression
import OpenSkyProgressionInterface
import OpenSkyQuests
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyScripting
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldConditions
import OpenSkyWorldInterface
public import OpenSkyWorldState

/// What `InventoryReadoutsAdapter` reads from the session.
@MainActor
public protocol InventoryReadoutsHost: AnyObject {
    var actorValues: any ActorValuePort { get }
    var actorWorld: any ActorWorldPort { get }
    var crime: any CrimePort { get }
    var gameSession: (any GameSessionPort)? { get }
    var journal: any JournalPort { get }
    var magic: any MagicPort { get }
    var player: any PlayerPort { get }
    var streamer: (any CellStreamerPort)? { get }
    var worldState: any WorldStateStorePort { get }
}

/// Part of `InventoryWorldAdapter`, over its own narrow host.
public struct InventoryReadoutsAdapter {
    public unowned let game: any InventoryReadoutsHost
}

extension InventoryReadoutsAdapter {
    /// A created alias reference has a spawn base; a placed one has its record's.
    public func questItemBases() -> Set<FormID> {
        guard let references = game.journal.runtime?.questObjectReferences() else { return [] }
        return Set(references.compactMap { key in
            if let spawn = game.worldState.component(ReferenceSpawnState.self, for: key) {
                return spawn.base
            }
            let entry = game.streamer?.referenceEntry(key: key)
            return entry?.placedReference?.base
        })
    }

    public var isPlayerSneaking: Bool {
        game.player.isSneaking
    }

    public func dropPlacement() -> DropPlacement? {
        guard let gameSession = game.gameSession, let location = game.streamer?.currentCellLocation
        else { return nil }
        return WorldItemRuntime.dropPlacement(
            in: location,
            eye: gameSession.freeFlyCamera.position,
            forward: gameSession.freeFlyCamera.forward
        )
    }

    public func nearestActorEntry() -> RuntimeReferenceEntry? {
        guard let gameSession = game.gameSession else { return nil }
        return game.streamer?.nearestActorEntry(to: gameSession.freeFlyCamera.position)
    }

    public func appearanceSkipReasons(forActor reference: FormID) -> [String] {
        game.streamer?.appearanceSkipReasons(forActor: reference) ?? []
    }

    public func theftBounty(of item: FormID, from reference: ReferenceKey) -> Int32 {
        game.crime.theftBounty(of: item, from: reference)
    }

    public func enchantmentLine(of item: FormID, on owner: ReferenceKey) -> String? {
        game.magic.enchantmentLine(of: item, on: game.actorWorld.actorValueHolder(for: owner))
    }

    public var enchantmentCacheReadout: EnchantmentCacheReadout {
        game.magic.enchantmentCacheReadout
    }

    public var gameDaysPassed: Float? {
        game.gameSession?.gameClock.daysPassed
    }

    public var gameMonth: Int? {
        game.gameSession?.gameClock.month
    }

    public func playerSpeechSkill() -> Float? {
        guard let speech = ActorValueIdentity.index(named: "Speechcraft") else { return nil }
        return game.actorValues.runtime?.value(at: speech, on: .player)
    }
}

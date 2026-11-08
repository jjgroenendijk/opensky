import OpenSkyActorPresentation
import OpenSkyActors
import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyCrime
import OpenSkyEffects
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyMagic
import OpenSkyMagicInterface
import OpenSkyMenus
import OpenSkyMenusInterface
import OpenSkyPerception
import OpenSkyPerceptionInterface
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyProgression
import OpenSkyQuests
import OpenSkyQuestsInterface
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyScripting
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWeather
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// What `ScriptPerkBindingsAdapter` reads from the session.
@MainActor
public protocol ScriptPerkBindingsHost: AnyObject {
    var actorWorld: any ActorWorldPort { get }
    var containerMenu: any ContainerMenuPort { get }
    var crime: any CrimePort { get }
    var factionWorld: any FactionWorldPort { get }
    var inventory: any InventoryPort { get }
    var magic: any MagicPort { get }
    var magicWorld: any MagicWorldPort { get }
    var perks: any PerkPort { get }
    var progression: any ProgressionPort { get }
    var worldState: any WorldStateStorePort { get }
}

/// Part of `ScriptWorldAdapter`, over its own narrow host.
public struct ScriptPerkBindingsAdapter {
    public unowned let game: any ScriptPerkBindingsHost
}

extension ScriptPerkBindingsAdapter {}

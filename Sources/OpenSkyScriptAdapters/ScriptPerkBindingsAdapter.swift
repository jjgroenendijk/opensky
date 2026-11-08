import OpenSkyActorPresentation
import OpenSkyActors
import OpenSkyAIPackages
public import OpenSkyCells
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
public import OpenSkyScripting
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
    public unowned let owner: ScriptWorldAdapter
    public unowned let game: any ScriptPerkBindingsHost
}

extension ScriptPerkBindingsAdapter {
    public func wireSpellNatives(
        bridge: PapyrusWorldStateBridge,
        provider: WorldDataStores
    ) {
        bridge.magicNatives.casterRuntime = { [weak game] in game?.magic.caster }
        bridge.magicNatives.isCommandedActor = { [weak game] key in
            game?.magic.commanded.contains { $0.actor == key } ?? false
        }
        bridge.magicEffectStore = provider.magicEffectStore
        bridge.formListStore = provider.formListStore
        bridge.keywordStore = provider.locationStore?.keywords
        bridge.magicNatives.dispelEffects = { [weak game] holder, predicate in
            game?.magic.dispelEffects(on: holder, where: predicate) ?? 0
        }
        bridge.magicNatives.applySpellHit = { [weak game] hit in
            game?.magicWorld.applySpellHit(hit) ?? .none
        }
        bridge.magicNatives.trapSoul = { [weak game] victim, caster in
            guard case .trapped = game?.magic.trapSoul(of: victim, by: caster) else { return false }
            return true
        }
        wirePerkNatives(bridge: bridge)
    }

    /// Granting a perk reconciles its abilities in the same call.
    private func wirePerkNatives(bridge: PapyrusWorldStateBridge) {
        bridge.progressionNatives.mutatePerks = { [weak game] mutation, perk, actor in
            guard let game, let holder = game.actorWorld.actorValueHolder(for: actor) else {
                return false
            }
            return switch mutation {
            case .add: game.perks.add(perk, to: holder)
            case .remove: game.perks.remove(perk, from: holder)
            }
        }
        bridge.progressionNatives.perkOwnership = { [weak game] key in
            game?.perks.ownership(of: key)
        }
        bridge.progressionNatives.advanceSkill = { [weak game] advance, index, magnitude in
            guard let progression = game?.progression else { return false }
            return switch advance {
            case .advance: progression.advanceSkill(index, byUse: magnitude)
            case .increment: progression.incrementSkill(index)
            }
        }
        // A zero delta is the read `Game.GetPerkPoints` makes.
        bridge.progressionNatives.modifyPerkPoints = { [weak game] delta in
            game?.progression.modifyPerkPoints(by: delta)
        }
        bridge.crimeNatives.crimeReporter = { [weak game] in game?.crime.reporter }
        bridge.crimeNatives.arrestSession = { [weak game] in game?.crime }
        game.crime.scriptedOwner = { [weak bridge] key in bridge?.scriptedOwner(of: key) }
        let worldState = game.worldState
        game.crime.scriptedOwnerRevision = { [weak worldState] in
            worldState?.revision(of: [.scriptedState]) ?? 0
        }
        bridge.crimeNatives.showBarterMenu = { [weak game] actor in
            guard let game, game.inventory.vendors != nil else { return nil }
            let text = game.containerMenu.openBarter(with: actor)
            return (game.containerMenu.isOpen && game.containerMenu.vendor != nil, text)
        }
        bridge.factionNatives = game.factionWorld.papyrusNatives()
        bridge.publishFactionReactions()
    }
}

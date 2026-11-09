// `ScriptPerkBindingsAdapter` joins the started session: what `wirePerkNatives` registered.

import OpenSkyActorPresentation
import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyEffects
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface
import OpenSkyMenusInterface
import OpenSkyPerceptionInterface
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyQuestsInterface
import OpenSkyRendering
import OpenSkyRuntimeState
public import OpenSkyScripting
import OpenSkyScriptingInterface
import OpenSkySessionInterface
import OpenSkyWeather
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// Granting a perk reconciles its abilities in the same call.
public struct ScriptPerkNativesWiring {
    public init(_ adapter: ScriptPerkBindingsAdapter, bridge: PapyrusWorldStateBridge) {
        bridge.progressionNatives
            .mutatePerks = { [weak game = adapter.game] mutation, perk, actor in
                guard let game, let holder = game.actorWorld.actorValueHolder(for: actor) else {
                    return false
                }
                return switch mutation {
                case .add: game.perks.add(perk, to: holder)
                case .remove: game.perks.remove(perk, from: holder)
                }
            }
        bridge.progressionNatives.perkOwnership = { [weak game = adapter.game] key in
            game?.perks.ownership(of: key)
        }
        bridge.progressionNatives
            .advanceSkill = { [weak game = adapter.game] advance, index, magnitude in
                guard let progression = game?.progression else { return false }
                return switch advance {
                case .advance: progression.advanceSkill(index, byUse: magnitude)
                case .increment: progression.incrementSkill(index)
                }
            }
        // A zero delta is the read `Game.GetPerkPoints` makes.
        bridge.progressionNatives.modifyPerkPoints = { [weak game = adapter.game] delta in
            game?.progression.modifyPerkPoints(by: delta)
        }
        bridge.crimeNatives.crimeReporter = { [weak game = adapter.game] in game?.crime.reporter }
        bridge.crimeNatives.arrestSession = { [weak game = adapter.game] in game?.crime }
        adapter.game.crime.scriptedOwner = { [weak bridge] key in bridge?.scriptedOwner(of: key) }
        let worldState = adapter.game.worldState
        adapter.game.crime.scriptedOwnerRevision = { [weak worldState] in
            worldState?.revision(of: [.scriptedState]) ?? 0
        }
        bridge.crimeNatives.showBarterMenu = { [weak game = adapter.game] actor in
            guard let game, game.inventory.vendors != nil else { return nil }
            let text = game.containerMenu.openBarter(with: actor)
            return (game.containerMenu.isOpen && game.containerMenu.vendor != nil, text)
        }
        bridge.factionNatives = adapter.game.factionWorld.papyrusNatives()
        bridge.publishFactionReactions()
    }
}
